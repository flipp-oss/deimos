# Generated Schema Classes

Deimos offers a way to generate classes from Avro schemas. These classes are documented
with YARD to aid in IDE auto-complete, and will help to move errors closer to the code.

### Overview of features
* Generate Schema classes from Avro Schemas
  * Initialize from decoded payload or from hash arguments
  * Comparison operator `==` to compare two instances of a `SchemaRecord`
  * RSpec matcher support
  * Transform instances of schema classes to hashes with `to_h`
  * Supports Primitive Types, Records, Enums, Maps, Arrays and Unions
* Use Schema Classes in your consumer/producer interfaces
  * Helps remove the problems with strings vs symbols as keys in the payloads
  * Can optionally disable consumer/producer schema class usage in your settings
* Miscellaneous
  * Guardfile to re-run `rake deimos:generate_schema_models` upon changes to your schemas

## Getting started

Before using schema classes, please ensure that your schema path and generated class path is set:
```ruby
config.schema.path 'path/to/schemas'
config.schema.generated_class_path 'path/to/generated/classes' # Defaults to 'app/lib/schema_classes'
```
You can run the following command to generate schema classes in your application
```shell
bundle exec rake deimos:generate_schema_classes
```
Additionally, you can enable a Guardfile that re-generates schema classes when your schemas are updated
```shell
rails g deimos:schema_class_guardfile
```
You can start using Generated Schema Classes in your applications consumers and producers by enabling the following configurations:
```ruby
config.schema.use_schema_class true
```
You can also disable the usage of schema classes for a particular consumer or producer with the `use_schema_class` config.

```ruby
Deimos.configure do
  consumer do
    class_name 'MyConsumer'
    topic 'MyTopic'
    schema 'MyTopicSchema'
    namespace 'my.namespace'
    key_config field: :id

    # Toggle the usage of this feature with this config
    use_schema_class false
  end

  producer do
    class_name 'MyProducer'
    topic 'MyTopic'
    schema 'MyTopicSchema'
    namespace 'my.namespace'
    key_config field: :id

    # Toggle the usage of this feature with this config
    use_schema_class false
  end
end
```

### Consumer
The consumer interface for using Schema Classes in your app relies on the `decode_message` method.
This does an automatic conversion from JSON hash into the Schemas generated Class and provides it
to the `consume`/`consume_batch` methods for their use.

Examples of consumers would look like this:
```ruby
# Consumer
class MyConsumer < Deimos::Consumer
  schema 'MySchema'
  namespace 'com.my-namespace'
  topic 'my-topic'
  key_config field: 'test_id'

  # @param payload [Deimos::SchemaRecord]
  # @param metadata [Hash]
  def consume(payload, metadata)
    # Same method as Phobos consumers.
    # payload is an instance of Deimos::MySchema rather than a hash.
    # metadata is a hash that contains information like :key and :topic.
    # You can interact with the schema class instance in the following way: 
    # payload.test_id 
    # payload.some_int
    # payload.to_h
  end

end
```

```ruby
# ActiveRecordConsumer
class MyActiveRecordConsumer < Deimos::ActiveRecordConsumer
  schema 'MySchema'
  namespace 'com.my-namespace'
  topic 'my-topic'
  key_config field: 'test_id'
  record_class Widget
 
  # The following methods will accept 
  # payload as an instance of Deimos::MySchema rather than a hash
  def fetch_record(klass, payload, key)
    super
  end

  def assign_key(record, payload, key)
    super
  end

  def record_attributes(payload, key)
    super.merge(:some_field => "some_value-#{payload.test_id}")
  end

  def record_key(payload)
    super
  end

  def process_message?(payload)
    super
  end
end

# == Schema Information
#
# Table name: widget
#
#  test_id       :string(255)      not null, primary key
#  some_int      :integer          not null
#  some_field    :string(255)      not null
```

### Producer
Similarly to the consumer interface, the producer interface for using Schema Classes in your app
relies on the `publish`/`publish_list` methods to convert a _provided_ instance of a Schema Class
into a hash that can be used freely by the Kafka client.

Examples of producers would look like this:
```ruby
# Producer
class MyProducer < Deimos::Producer
  schema 'MySchema'
  namespace 'com.my-namespace'
  topic 'my-topic'
  key_config field: 'test_id'

  class << self
    # @param test_id [String]
    # @param some_int [Integer]
    def self.send_a_message(test_id, some_int)
      # Instead of sending in a Hash object to the publish or publish_list method,      
      # you can initialize an instance of your schema class and send that in.
      message = Deimos::MySchema.new(
        test_id: test_id,
        some_int: some_int
      )
      self.publish(message)
      self.publish_list([message])
    end

  end

end
```

```ruby
# ActiveRecordProducer
class MyActiveRecordProducer < Deimos::ActiveRecordProducer
  schema 'MySchema'
  namespace 'com.my-namespace'
  topic 'my-topic'
  key_config field: 'test_id'
  record_class Widget
 
  # @param payload [Deimos::SchemaRecord]
  # @param _record [Widget]
  def self.generate_payload(attributes, _record)
    # The generate_payload will convert your ActiveRecord into a SchemaRecord
    # You will be able to use `res` as an instance of Deimos::MySchema and set
    # values that are not on your ActiveRecord schema.
    res = super
    res.some_value = "some_value-#{payload.test_id}"
    res
  end
end

# == Schema Information
#
# Table name: widget
#
#  test_id       :string(255)      not null, primary key
#  some_int      :integer          not null
```
