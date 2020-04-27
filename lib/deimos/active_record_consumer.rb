# frozen_string_literal: true

require 'deimos/activerecord/batch_consumption'
require 'deimos/activerecord/message_consumption'
require 'deimos/activerecord/schema_model_converter'
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
      @converter = ActiveRecord::SchemaModelConverter.new(self.class.decoder, @klass)

      if self.class.config[:key_schema]
        @key_converter = ActiveRecord::SchemaModelConverter.new(self.class.key_decoder, @klass)
      end
    end

    # Get unique key for the ActiveRecord instance from the incoming key.
    # Override this method (with super) to customize the set of attributes that
    # uniquely identifies each record in the database.
    # @param key [String] The encoded key.
    # @return [Hash] The key attributes.
    def record_key(key)
      decoded_key = decode_key(key)

      if decoded_key.nil?
        {}
      elsif decoded_key.is_a?(Hash)
        @key_converter.convert(decoded_key)
      else
        { @klass.primary_key => decoded_key }
      end
    end

    # Override this method (with `super`) if you want to add/change the default
    # attributes set to the new/existing record.
    # @param payload [Hash]
    # @param key [String]
    def record_attributes(payload, key=nil)
      @converter
        .convert(payload)
        .merge(record_key(key))
    end
  end
end
