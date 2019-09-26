# frozen_string_literal: true

require 'deimos/activerecord/batch_consumption'
require 'deimos/activerecord/message_consumption'
require 'deimos/consumer'

module Deimos
  class ActiveRecordConsumer < Consumer
    include ActiveRecord::MessageConsumption
    include ActiveRecord::BatchConsumption

    class << self
      # param klass [Class < ActiveRecord::Base] the class used to save to the
      # database.
      def record_class(klass)
        config[:record_class] = klass
      end
    end

    # Setup
    def initialize
      @klass = self.class.config[:record_class]

      @converter = SchemaModelConverter.new(
        self.class.decoder.avro_schema,
        @klass
      )

      if self.class.config[:key_schema] # rubocop:disable Style/GuardClause
        @key_converter = SchemaModelConverter.new(
          self.class.key_decoder.avro_schema,
          @klass
        )
      end
    end

  protected

    # Get attributes for new/upserted records in the database. Override this
    # method (with super) to customize the set of attributes used to instantiate
    # records.
    # @param payload [Hash] The decoded message payload.
    # @param key [Hash] The decoded message key.
    # @return [Hash|nil] Attribute set for the upserted record. nil to skip
    # insertion.
    def record_attributes(key, payload)
      attributes = @converter.convert(payload)

      attributes.merge(record_key(key))
    end
  end
end