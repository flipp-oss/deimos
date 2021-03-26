require 'deimos/schema_model'

module Deimos
  # :nodoc:
  class GeneratedSchema < SchemaModel
    # @!attribute [rw] status
    # @return [String]
    attr_accessor :a_string
    # @!attribute [rw] status
    # @return [Integer]
    attr_accessor :a_int
    # @!attribute [rw] status
    # @return [Integer]
    attr_accessor :a_long
    # @!attribute [rw] status
    # @return [Float]
    attr_accessor :a_float
    # @!attribute [rw] status
    # @return [Float]
    attr_accessor :a_double
    # @!attribute [rw] status
    # @return [Deimos::GeneratedAnEnumEnum]
    attr_accessor :an_enum
    # @!attribute [rw] status
    # @return [Array<Integer>]
    attr_accessor :an_array
    # @!attribute [rw] status
    # @return [Hash<String, String>]
    attr_accessor :a_map
    # @!attribute [rw] status
    # @return [String]
    attr_accessor :timestamp
    # @!attribute [rw] status
    # @return [String]
    attr_accessor :message_id
    # @!attribute [rw] status
    # @return [Deimos::GeneratedARecordSchema]
    attr_accessor :a_record

    # @override
    def initialize(a_string:, a_int:, a_long:, a_float:, a_double:, an_enum:, an_array:, a_map:, timestamp:, message_id:, a_record:)
      super()
      @a_string = a_string
      @a_int = a_int
      @a_long = a_long
      @a_float = a_float
      @a_double = a_double
      @an_enum = an_enum
      @an_array = an_array
      @a_map = a_map
      @timestamp = timestamp
      @message_id = message_id
      @a_record = a_record
    end

    # @override
    def schema
      'Generated'
    end

    # @override
    def namespace
      'com.my-namespace'
    end

    # @override
    def to_h
      {
        'a_string' => @a_string,
        'a_int' => @a_int,
        'a_long' => @a_long,
        'a_float' => @a_float,
        'a_double' => @a_double,
        'an_enum' => @an_enum,
        'an_array' => @an_array,
        'a_map' => @a_map,
        'timestamp' => @timestamp,
        'message_id' => @message_id,
        'a_record' => @a_record,
      }
    end

  end
end
