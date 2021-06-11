# frozen_string_literal: true

module Deimos
  # :nodoc:
  class Generated < SchemaRecord
    # @return [String]
    attr_accessor :a_string
    # @return [Integer]
    attr_accessor :a_int
    # @return [Integer]
    attr_accessor :a_long
    # @return [Float]
    attr_accessor :a_float
    # @return [Float]
    attr_accessor :a_double
    # @return [nil, Integer]
    attr_accessor :an_optional_int
    # @return [Deimos::AnEnum]
    attr_accessor :an_enum
    # @return [Array<Integer>]
    attr_accessor :an_array
    # @return [Hash<String, String>]
    attr_accessor :a_map
    # @return [String]
    attr_accessor :timestamp
    # @return [String]
    attr_accessor :message_id
    # @return [Deimos::ARecord]
    attr_accessor :a_record

    # @override
    def initialize(a_string:, a_int:, a_long:, a_float:, a_double:, an_optional_int:, an_enum:, an_array:, a_map:, timestamp:, message_id:, a_record:)
      super()
      @a_string = a_string
      @a_int = a_int
      @a_long = a_long
      @a_float = a_float
      @a_double = a_double
      @an_optional_int = an_optional_int
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
        'an_optional_int' => @an_optional_int,
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
