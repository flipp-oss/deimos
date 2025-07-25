# frozen_string_literal: true

# This file is autogenerated by Deimos, Do NOT modify
module Schemas; module MyNamespace
  ### Primary Schema Class ###
  # Autogenerated Schema for Record at com.my-namespace.MySchemaWithDateTimes
  class MySchemaWithDateTime < Deimos::SchemaClass::Record

    ### Attribute Accessors ###
    # @return [String]
    attr_accessor :test_id
    # @return [Integer, nil]
    attr_accessor :updated_at
    # @return [nil, Integer]
    attr_accessor :some_int
    # @return [nil, Integer]
    attr_accessor :some_datetime_int
    # @return [String]
    attr_accessor :timestamp

    # @override
    def initialize(_from_message: false, test_id: nil,
                   updated_at: nil,
                   some_int: nil,
                   some_datetime_int: nil,
                   timestamp: nil)
      @_from_message = _from_message
      super
      self.test_id = test_id
      self.updated_at = updated_at
      self.some_int = some_int
      self.some_datetime_int = some_datetime_int
      self.timestamp = timestamp
    end

    # @override
    def schema
      'MySchemaWithDateTimes'
    end

    # @override
    def namespace
      'com.my-namespace'
    end

    # @override
    def as_json(_opts={})
      {
        'test_id' => @test_id,
        'updated_at' => @updated_at,
        'some_int' => @some_int,
        'some_datetime_int' => @some_datetime_int,
        'timestamp' => @timestamp
      }
    end
  end
end; end
