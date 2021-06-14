# frozen_string_literal: true

module Deimos
  # :nodoc:
  class ARecord < SchemaRecord
    # @return [String]
    attr_accessor :a_record_field

    # @override
    def initialize(a_record_field:)
      super()
      @a_record_field = a_record_field
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
      'ARecord'
    end

    # @override
    def namespace
      'com.my-namespace'
    end

    # @override
    def to_h
      {
        'a_record_field' => @a_record_field
      }
    end
  end
end
