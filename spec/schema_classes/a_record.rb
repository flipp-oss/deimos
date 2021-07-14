# frozen_string_literal: true

module Deimos
  # :nodoc:
  class ARecord < SchemaRecord
    # @return [String]
    attr_accessor :a_record_field

    # @override
    def initialize(**kwargs)
      super()
      args = kwargs.with_indifferent_access
      @a_record_field = args[:a_record_field]
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
