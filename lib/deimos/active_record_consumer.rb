# frozen_string_literal: true

require 'deimos/active_record_consume/batch_consumption'
require 'deimos/active_record_consume/message_consumption'
require 'deimos/active_record_consume/schema_model_converter'
require 'deimos/consumer'

module Deimos
  # Basic ActiveRecord consumer class. Consumes messages and upserts them to
  # the database. For tombstones (null payloads), deletes corresponding
  # records from the database. Can operate in either message-by-message mode
  # or in batch mode.
  #
  # In batch mode, ActiveRecord callbacks will be skipped and messages will
  # be batched to minimize database calls.

  # To configure batch vs. message mode, change the delivery mode of your
  # Phobos listener.
  # Message-by-message -> use `delivery: message` or `delivery: batch`
  # Batch -> use `delivery: inline_batch`
  class ActiveRecordConsumer < Consumer
    include ActiveRecordConsume::MessageConsumption
    include ActiveRecordConsume::BatchConsumption

    class << self
      # param klass [Class < ActiveRecord::Base] the class used to save to the
      # database.
      def record_class(klass)
        config[:record_class] = klass
      end

      # param val [Boolean] Turn pre-compaction of the batch on or off. If true,
      # only the last message for each unique key in a batch is processed.
      def compacted(val)
        config[:compacted] = val
      end
    end

    # Setup
    def initialize
      @klass = self.class.config[:record_class]
      @converter = ActiveRecordConsume::SchemaModelConverter.new(self.class.decoder, @klass)

      if self.class.config[:key_schema]
        @key_converter = ActiveRecordConsume::SchemaModelConverter.new(self.class.key_decoder, @klass)
      end

      @compacted = self.class.config[:compacted] != false
    end

    # Override this method (with `super`) if you want to add/change the default
    # attributes set to the new/existing record.
    # @param payload [Hash]
    # @param _key [String]
    def record_attributes(payload, _key=nil)
      @converter.convert(payload)
    end
  end
end
