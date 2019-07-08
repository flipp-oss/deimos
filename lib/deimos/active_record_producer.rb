# frozen_string_literal: true

require 'deimos/producer'

module Deimos
  # Class which automatically produces a record when given an ActiveRecord
  # instance or a list of them. Just call `send_events` on a list of records
  # and they will be auto-published. You can override `generate_payload`
  # to make changes to the payload before it's published.
  #
  # You can also call this with a list of hashes representing attributes.
  # This is common when using activerecord-import.
  class ActiveRecordProducer < Producer
    class << self
      # Indicate the class this producer is working on.
      # @param klass [Class]
      # @param refetch [Boolean] if true, and we are given a hash instead of
      # a record object, refetch the record to pass into the `generate_payload`
      # method.
      def record_class(klass, refetch: true)
        config[:record_class] = klass
        config[:refetch_record] = refetch
      end

      # @param record [ActiveRecord::Base]
      # @param force_send [Boolean]
      def send_event(record, force_send: false)
        send_events([record], force_send: force_send)
      end

      # @param records [Array<ActiveRecord::Base>]
      # @param force_send [Boolean]
      def send_events(records, force_send: false)
        primary_key = config[:record_class]&.primary_key
        messages = records.map do |record|
          if record.respond_to?(:attributes)
            attrs = record.attributes.with_indifferent_access
          else
            attrs = record.with_indifferent_access
            if config[:refetch_record] && attrs[primary_key]
              record = config[:record_class].find(attrs[primary_key])
            end
          end
          generate_payload(attrs, record).with_indifferent_access
        end
        self.publish_list(messages, force_send: force_send)
      end

      # Generate the payload, given a list of attributes or a record..
      # Can be overridden or added to by subclasses.
      # @param attributes [Hash]
      # @param _record [ActiveRecord::Base] May be nil if refetch_record
      # is not set.
      # @return [Hash]
      def generate_payload(attributes, _record)
        schema = self.encoder.avro_schema
        payload = attributes.stringify_keys
        payload.delete_if do |k, _|
          k.to_sym != :payload_key && !schema.fields.find { |f| f.name == k }
        end
      end
    end
  end
end
