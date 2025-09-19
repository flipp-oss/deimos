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
      # @param klass [Class<ActiveRecord::Base>] the class used to save to the
      # database.
      # @return [void]
      def record_class(klass)
        config[:record_class] = klass
      end

      # @param val [Boolean] Turn pre-compaction of the batch on or off. If true,
      # only the last message for each unique key in a batch is processed.
      # @return [void]
      def compacted(val)
        config[:compacted] = val
      end

      # @param limit [Integer] Maximum number of transactions in a single database call.
      # @return [void]
      def max_db_batch_size(limit)
        config[:max_db_batch_size] = limit
      end

    end

    # @return [Boolean]
    def replace_associations
      self.topic.replace_associations
    end

    # @return [String,nil]
    def bulk_import_id_column
      self.topic.bulk_import_id_column
    end

    # @return [Proc]
    def bulk_import_id_generator
      topic.bulk_import_id_generator
    end

    # @return [Boolean]
    def save_associations_first
      topic.save_associations_first
    end

    def key_decoder
      self.topic.serializers[:key]&.backend
    end

    # Setup
    def initialize
      @klass = self.class.config[:record_class]
      @compacted = self.class.config[:compacted] != false
    end

    def converter
      decoder = self.topic.deserializers[:payload].backend
      @converter ||= ActiveRecordConsume::SchemaModelConverter.new(decoder, @klass)
    end

    def key_converter
      decoder = self.topic.deserializers[:key]&.backend
      return nil if decoder.nil?
      @key_converter ||= ActiveRecordConsume::SchemaModelConverter.new(decoder, @klass)
    end

    # Override this method (with `super`) if you want to add/change the default
    # attributes set to the new/existing record.
    # @param payload [Hash,Deimos::SchemaClass::Record]
    # @param _key [String]
    # @return [Hash]
    def record_attributes(payload, _key=nil)
      self.converter.convert(payload)
    end

    # Indicates whether to delete the given message. Defaults to checking if the message
    # payload is nil.
    # @param message [Deimos::Message]
    # @return [Boolean]
    def delete_record?(message)
      message.payload.nil?
    end

    # Override this message to conditionally save records
    # @param _payload [Hash,Deimos::SchemaClass::Record] The kafka message
    # @return [Boolean] if true, record is created/update.
    #   If false, record processing is skipped but message offset is still committed.
    def process_message?(_payload)
      true
    end
  end
end
