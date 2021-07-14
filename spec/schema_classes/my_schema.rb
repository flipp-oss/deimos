# frozen_string_literal: true

module Deimos
  # :nodoc:
  class MySchema < SchemaRecord
    # @return [String]
    attr_accessor :test_id
    # @return [Integer]
    attr_accessor :some_int

    # @override
    def initialize(**kwargs)
      super()
      args = kwargs.with_indifferent_access
      @test_id = args[:test_id]
      @some_int = args[:some_int]
    end

    # @override
    def self.initialize_from_payload(payload)
      return unless payload.any?

      args = {}
      payload.each do |key, value|
        args[key.to_sym] = value
      end
      self.new(**args)
    end

    # @override
    def schema
      'MySchema'
    end

    # @override
    def namespace
      'com.my-namespace'
    end

    # @override
    def to_h
      {
        'test_id' => @test_id,
        'some_int' => @some_int
      }
    end
  end
end
