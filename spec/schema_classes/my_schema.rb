# frozen_string_literal: true

module Deimos
  # :nodoc:
  class MySchema < SchemaRecord
    # @return [String]
    attr_accessor :test_id
    # @return [Integer]
    attr_accessor :some_int

    # @override
    def initialize(test_id:, some_int:)
      super()
      @test_id = test_id
      @some_int = some_int
    end

    # @override
    def self.initialize_from_hash(hash)
      return unless hash.any?

      payload = {}
      hash.each do |key, value|
        payload[key.to_sym] = value
      end
      self.new(payload)
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
