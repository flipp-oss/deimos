# frozen_string_literal: true

module Deimos
  module ActiveRecordConsume
    # Methods for consuming individual messages and saving them to the database
    # as ActiveRecord instances.
    module MessageConsumption
      # Find the record specified by the given payload and key.
      # Default is to use the primary key column and the value of the first
      # field in the key.
      # @param klass [Class < ActiveRecord::Base]
      # @param _payload [Hash]
      # @param key [Object]
      # @return [ActiveRecord::Base]
      def fetch_record(klass, _payload, key)
        klass.unscoped.where(klass.primary_key => key).first
      end

      # Assign a key to a new record.
      # @param record [ActiveRecord::Base]
      # @param _payload [Hash]
      # @param key [Object]
      def assign_key(record, _payload, key)
        record[record.class.primary_key] = key
      end

      # :nodoc:
      def consume(payload, metadata)
        unless process_message?(payload)
          Deimos.config.logger.debug(
            message: 'Skipping processing of message',
            payload: decoded_payload,
            metadata: metadata
          )
          return
        end

        key = metadata.with_indifferent_access[:key]
        klass = self.class.config[:record_class]
        record = fetch_record(klass, (payload || {}).with_indifferent_access, key)
        if payload.nil?
          destroy_record(record)
          return
        end
        if record.blank?
          record = klass.new
          assign_key(record, payload, key)
        end

        # for backwards compatibility
        # TODO next major release we should deprecate this
        attrs = if self.method(:record_attributes).parameters.size == 2
                  record_attributes(payload.with_indifferent_access, key)
                else
                  record_attributes(payload.with_indifferent_access)
                end
        # don't use attributes= - bypass Rails < 5 attr_protected
        attrs.each do |k, v|
          record.send("#{k}=", v)
        end
        record.created_at ||= Time.zone.now if record.respond_to?(:created_at)
        record.updated_at = Time.zone.now if record.respond_to?(:updated_at)
        record.save!
      end

      # Destroy a record that received a null payload. Override if you need
      # to do something other than a straight destroy (e.g. mark as archived).
      # @param record [ActiveRecord::Base]
      def destroy_record(record)
        record&.destroy
      end
    end
  end
end
