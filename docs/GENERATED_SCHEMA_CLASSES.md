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
* Misc
  * Guardfile to re-run `rake deimos:generate_schema_models` upon changes to your schemas

## Getting started

Before using schema classes, please ensure that your schema path is set:
```ruby
config.schema.path 'path/to/schemas' # Uses 'app/schemas' by default
```
You can start using Generated Schema Classes in your app by enabling the following configurations:
```ruby
config.schema.use_schema_class true
config.schema.generated_class_path 'path/to/generated/classes' # Defaults to 'app/lib/schema_classes'
```
You can run the following command to generate schema classes
```shell
bundle exec rake deimos:generate_schema_classes
```
Additionally, you can enable a Guardfile that re-generates schema classes when your schemas are updated
```shell
rails g deimos:schema_class_guardfile
```

### Consumer
The consumer interface for using Schema Classes in your app relies on the `decode_message` method.
This does an automatic conversion from JSON hash into the Schemas generated Class and provides it
to the `consume`/`consume_batch` methods for their use.

You can toggle or disable the usage of schema classes for a particular consumer with the
`use_schema_class` config.
```ruby
Deimos.configure do
  consumer do
    class_name 'MyConsumer'
    topic 'MyTopic'
    schema 'MyTopicSchema'
    namespace 'my.namespace'
    key_config field: :id

    # Toggle the usage of this feature with the following
    use_schema_class false
  end
end
```

### Producer
Similarly to the consumer interface, the producer interface for using Schema Classes in your app
relies on the `publish`/`publish_list` methods to convert a provided instance of a Schema Class
into a hash that can be used freely by the Kafka client.

You can toggle or disable the usage of schema classes for a particular producer with the
`use_schema_class` config.
```ruby
Deimos.configure do
  producer do
    class_name 'MyProducer'
    topic 'MyTopic'
    schema 'MyTopicSchema'
    namespace 'my.namespace'
    key_config field: :id

    use_schema_class false
  end
end
```

### Examples

#### Consumer
```ruby
# Consumer
class MyConsumer < Deimos::Consumer
  schema 'MySchema'
  namespace 'com.my-namespace'
  topic 'my-topic'
  key_config field: 'test_id'

  # @param payload [Deimos::SchemaRecord]
  # @param _metadata [Hash]
  def consume(payload, _metadata)
    # Inside of this block, `payload` will be an instance of Deimos::MySchema.
    # You can do anything you want with it!
    payload.test_id
    payload.some_int
    payload.to_h
  end
end
```

#### Producer
```ruby
# Producer
class MyProducer < Deimos::Producer
  schema 'MySchema'
  namespace 'com.my-namespace'
  topic 'my-topic'
  key_config field: 'test_id'

  # @param test_id [String]
  # @param some_int [Integer]
  def self.send_a_message(test_id, some_int)
    # Initialize an instance of your schema class.
    message = Deimos::MySchema.new(
      test_id: test_id,
      some_int: some_int
    )
    # You can provide it directly to the `publish` or `publish_list` method.
    self.publish(message)
    self.publish_list([message])
  end
end
```

#### ActiveRecord
```ruby
class MyActiveRecordConsumer < Deimos::ActiveRecordConsumer
  schema 'MySchema'
  namespace 'com.my-namespace'
  topic 'my-topic'
  key_config field: 'test_id'
  record_class Widget
 
  # @param payload [Deimos::SchemaRecord]
  # @param key [Deimos::SchemaRecord]
  def record_attributes(payload)
    # Inside of this block, `payload` will be an instance of Deimos::MySchema.
    # You can do anything you want with it.
    super.merge(test_id: payload.test_id, some_int: payload.some_int)
  end
end

# == Schema Information
#
# Table name: widget
#
#  test_id       :string(255)      not null, primary key
#  some_int      :integer          not null
```

```ruby
class MyActiveRecordProducer < Deimos::ActiveRecordProducer
  schema 'MySchema'
  namespace 'com.my-namespace'
  topic 'my-topic'
  key_config field: 'test_id'
  record_class Widget
 
  # @param payload [Deimos::SchemaRecord]
  # @param _record [Widget]
  def self.generate_payload(attributes, _record)
    res = super
    # The generate_payload will convert your ActiveRecord into a SchemaRecord
    # Inside of this block, you will be able to use `res` as an instance of Deimos::MySchema.
    res.test_id = "#{res.some_int}"
    res.some_int += 123
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