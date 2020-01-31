# Database Backend Design

Kafka is a messaging protocol, while databases are transactional and relational. 
Marrying the two (e.g. by using Kafka to publish changes to a database table)
is not a simple task. This document describes the problem and the current
implementation. There will be references to microservices architecture as that
informs some of the discussion.

## A Pure Solution

The purest solution is to use Kafka as the "source of truth" by first publishing
all messages synchronously to Kafka, and then using a consumer to read these 
messages back into the database. If there are any errors sending to Kafka,
the thread will crash and no data would be written. If there are errors
reading the data back into the database, the data remains in Kafka and can
be re-read at any time.

There are several real-world problems with this pure solution:

1. The solution assumes that creating a consumer is a simple task, which is 
   definitely not the case. Depending on how many topics are being produced to,
   a separate consumer thread per topic (which is how Phobos works) is overkill.
   The other option is to introduce an entirely new consumer service to handle
   consuming the topics we've already produced, which is even more overkill.
2.  For CRUD interfaces or any other UI that saves data to the database, we do 
    not want to use an asynchronous method to ensure that data is published to 
    Kafka before saving, and then being able to serve that data back to the user
    in a single API call, which is a common use case. 
    This could involve a large amount of added complexity and may force the user 
    to wait unnecessarily.
3.  We want to make use of database transactions - i.e. if an error happens 
    saving one record, the others should roll back. Once a message is written to 
    Kafka, it can't be "rolled back" easily. Kafka transactions do exist but 
    they are not widely supported in Kafka clients, and we still would be 
    faced with the fact that one transaction (Kafka or database) could finish 
    and then the process could be killed before the other one could be finished.
4.  We want to make use of auto-increment database IDs - we can't do this if we 
    write to Kafka first.
5.  Kafka is an external dependency. If either the DB **or** Kafka goes down, 
    our app becomes unusable.

Using tools like Kafka Connect and Debezium are not ideal because:

1. They are tied very closely to the internal relational schema, which is not 
   ideal, especially for legacy systems. It makes it nearly impossible to make 
   internal changes.
2. They are separate services and connectors must be created for each 
   microservice separately, which is a large overhead.

## Database Backend Solution

We will be using the database itself as the source of our Kafka messages. 
We will first write our messages to a database table and then asynchronously 
send those messages to Kafka. This solves our problems:

1.  The database is the (interim) source of truth. The Kafka message log is 
    essentially the changelog, which we can tail and send out. If our producing 
    thread errors out, a new one will simply pick up where it left off. 
    This ensures eventual consistency.
2.  Because we are only using the database in the main application thread, we do 
    not need to wait for Kafka production to continue and can return immediately.
3.  Because we are only saving to the database, we can use transactions normally 
    - if a transaction fails, it will roll back along with any Kafka messages we 
    intended to send.
4.  Records are saved normally and messages are created after that, all as part 
    of the transaction, so we can use database IDs as usual.
5.  We remove Kafka entirely as a dependency for normal work - the Kafka sending 
    piece is a separate thread.
    
The one downside to this is a slight delay (generally less than 1 second) 
between the message being written to the database and sent to Kafka - in most 
cases this is an acceptable limitation.

### The Implementation

The database backend consists of three tables:

* `kafka_messages` - this keeps track of the messages that were "published",
  including the payload, topic, key and partition key. These messages
  are *raw data* - all processing, including schema-encoding, must happen
  upstream before they are inserted.
* `kafka_topic_info` - this table is essentially a lock table used to ensure
  that only one producer thread is ever "working" on a topic at a time.

The backend code structure is such that when a producer calls `publish_list`,
it delegates that logic to the configured backend. A backend of `kafka`
or `kafka_async` will use existing Phobos logic. A backend of `db` will use
the database backend instead.

### "Publishing" A Message

When `publish_list` is called when the database backend is configured, 
Deimos will instead save the message to the `kafka_messages` table.

### Sending Messages to Kafka

The database executor is started by calling `Deimos.start_db_backend!`
with a specified number of threads. These threads will continually scan the
two messages tables and send the messages to Kafka. 

The algorithm for sending the messages makes use of the `kafka_topic_info` table as a lock table. There is also an `error` boolean column which is used to track when a topic has errored out. When this happens, the topic is marked as errored and will not be picked up for the next minute, after which it will be treated as any other topic. The full algorithm is as follows:

* Create a UUID for the thread - this is created once on thread start.
* Find all unique topics in the `kafka_messages` table.
* For each topic:
  * Create an entry in `kafka_topic_info` for this topic if it doesn't exist.
  * Run the following query: 
  
      ```sql
            UPDATE kafka_topic_info 
            SET locked_by=#{uuid}, locked_at=NOW(), error=0
            WHERE (locked_by IS NULL AND error=0) OR locked_at < #{1.minute.ago} 
            LIMIT 1
      ```
     * If the lock was unsuccessful, move on to the next topic in the list
  * Find the first 1000 messages in `kafka_messages` for that topic, ordered by ID (insertion order).
  * Created a unique UUID for this batch of messages, and update the `session_id` column for this batch of messages using the UUID.
  * Send the messages synchronously to Kafka with all brokers acking the message.
  * Delete the KafkaMessage records from the DB utilizing the uniquely created UUID.
  * Update the `locked_at` timestamp in `kafka_topic_info` to `NOW()` to ensure liveness in case a particular batch took longer than expected to send.
  * If the current batch is 1000 messages, repeat with the next batch of
    messages until it returns less than 1000
  * When all batches are sent:
      * Unlock the topic by updating the `kafka_topic_info` for this topic, setting `locked_by=NULL, locked_at=NULL, error=0, retries=0`
      * Move on to the next topic
   * If there are errors sending a batch:
     * Update the `kafka_topic_info` for this topic to have `locked_by=NULL, locked_at=NULL, error=1, retries=retries+1` - this will effectively keep it
       locked for the next minute
     * Move on to the next topic.
* When all topics are done, or if there are no topics, sleep for 0.5 seconds and begin again.

### Class / Method Design

The algorithm is split up into the following classes:

* Backends::Db - this is the class that saves the message to the database.
* KafkaMessage: This is an ActiveRecord class that handle saving the messages to the database and querying them.
* KafkaTopicInfo: This is an ActiveRecord class that handles locking, unlocking and heartbeating.
* Utils::SignalHandler: This is the equivalent of Phobos's Runner class and
  handles the KILL, INT and TERM signals to gracefully shut down the threads.
* Utils::Executor is the equivalent of Phobos's Executor class and handles
  the thread pool of producer threads.
* Utils::DbProducer is the producer thread itself which implements most of the
  algorithm listed above.

### Caveats

There is one disadvantage of this pattern, which is that it is possible for events to be sent multiple times if the thread which sent the messages dies before being able to delete it from the database. In general this is an acceptable effect, since Kafka only guarantees at-least-once delivery in any case.
