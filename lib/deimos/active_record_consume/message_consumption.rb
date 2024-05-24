# frozen_string_literal: true

require 'deimos/consume/message_consumption'

module Deimos
  module ActiveRecordConsume
    # Methods for consuming individual messages and saving them to the database
    # as ActiveRecord instances.
    module MessageConsumption
      include Deimos::Consume::MessageConsumption
      # Find the record specified by the given payload and key.
      # Default is to use the primary key column and the value of the first
      # field in the key.
      # @param klass [Class<ActiveRecord::Base>]
      # @param _payload [Hash,Deimos::SchemaClass::Record]
      # @param key [Object]
      # @return [ActiveRecord::Base]
      def fetch_record(klass, _payload, key)
        fetch_key = key.is_a?(Hash) && key.size == 1 ? key.values.first : key
        klass.unscoped.where(klass.primary_key => fetch_key).first
      end

      # Assign a key to a new record.
      # @param record [ActiveRecord::Base]
      # @param _payload [Hash,Deimos::SchemaClass::Record]
      # @param key [Object]
      # @return [void]
      def assign_key(record, _payload, key)
        record[record.class.primary_key] = key
      end

      # @param message [Karafka::Messages::Message]
      def consume_message(message)
        unless self.process_message?(message)
          Deimos::Logging.log_debug(
              message: 'Skipping processing of message',
              payload: message.payload.to_h,
              metadata: Deimos::Logging.metadata_log_text(message.metadata)
            )
          return
        end

        klass = self.class.config[:record_class]
        record = fetch_record(klass, message.payload.to_h.with_indifferent_access, message.key)
        if message.payload.nil?
          destroy_record(record)
          return
        end
        if record.blank?
          record = klass.new
          assign_key(record, message.payload, message.key)
        end

        attrs = record_attributes(message.payload.to_h.with_indifferent_access, message.key)
        # don't use attributes= - bypass Rails < 5 attr_protected
        attrs.each do |k, v|
          record.send("#{k}=", v)
        end
        save_record(record)
      end

      # @param record [ActiveRecord::Base]
      # @return [void]
      def save_record(record)
        record.created_at ||= Time.zone.now if record.respond_to?(:created_at)
        record.updated_at = Time.zone.now if record.respond_to?(:updated_at)
        record.save!
      end

      # Destroy a record that received a null payload. Override if you need
      # to do something other than a straight destroy (e.g. mark as archived).
      # @param record [ActiveRecord::Base]
      # @return [void]
      def destroy_record(record)
        record&.destroy
      end
    end
  end
end
