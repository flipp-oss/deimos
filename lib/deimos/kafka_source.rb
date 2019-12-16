# frozen_string_literal: true

module Deimos
  # Represents an object which needs to inform Kafka when it is saved or
  # bulk imported.
  module KafkaSource
    extend ActiveSupport::Concern

    included do
      after_create(:send_kafka_event_on_create)
      after_update(:send_kafka_event_on_update)
      after_destroy(:send_kafka_event_on_destroy)
    end

    # Send the newly created model to Kafka.
    def send_kafka_event_on_create
      return unless self.persisted?
      return unless self.class.kafka_config[:create]

      self.class.kafka_producers.each { |p| p.send_event(self) }
    end

    # Send the newly updated model to Kafka.
    def send_kafka_event_on_update
      return unless self.class.kafka_config[:update]

      producers = self.class.kafka_producers
      fields = producers.flat_map(&:watched_attributes).uniq
      fields -= ['updated_at']
      # Only send an event if a field we care about was changed.
      any_changes = fields.any? do |field|
        field_change = self.previous_changes[field]
        field_change.present? && field_change[0] != field_change[1]
      end
      return unless any_changes

      producers.each { |p| p.send_event(self) }
    end

    # Send a deletion (null payload) event to Kafka.
    def send_kafka_event_on_destroy
      return unless self.class.kafka_config[:delete]

      self.class.kafka_producers.each { |p| p.publish_list([self.deletion_payload]) }
    end

    # Payload to send after we are destroyed.
    # @return [Hash]
    def deletion_payload
      { payload_key: self[self.class.primary_key] }
    end

    # :nodoc:
    module ClassMethods
      # @return [Hash]
      def kafka_config
        {
          update: true,
          delete: true,
          import: true,
          create: true
        }
      end

      # @return [Array<Deimos::ActiveRecordProducer>] the producers to run.
      def kafka_producers
        raise NotImplementedError if self.method(:kafka_producer).
          owner == Deimos::KafkaSource

        [self.kafka_producer]
      end

      # Deprecated - use #kafka_producers instead.
      # @return [Deimos::ActiveRecordProducer] the producer to use.
      def kafka_producer
        raise NotImplementedError if self.method(:kafka_producers).
          owner == Deimos::KafkaSource

        self.kafka_producers.first
      end

      # This is an internal method, part of the activerecord_import gem. It's
      # the one that actually does the importing, having already normalized
      # the inputs (arrays, hashes, records etc.)
      # Basically we want to first do the import, then reload the records
      # and send them to Kafka.
      def import_without_validations_or_callbacks(column_names,
                                                  array_of_attributes,
                                                  options={})
        results = super
        return unless self.kafka_config[:import]
        return if array_of_attributes.empty?

        # This will contain an array of hashes, where each hash is the actual
        # attribute hash that created the object.
        ids = if results.is_a?(Array)
                results[1]
              elsif results.respond_to?(:ids)
                results.ids
              else
                []
              end
        if ids.blank?
          # re-fill IDs based on what was just entered into the DB.
          if self.connection.adapter_name.downcase =~ /sqlite/
            last_id = self.connection.select_value('select last_insert_rowid()')
            ids = ((last_id - array_of_attributes.size + 1)..last_id).to_a
          else # mysql
            last_id = self.connection.select_value('select LAST_INSERT_ID()')
            ids = (last_id..(last_id + array_of_attributes.size)).to_a
          end
        end
        array_of_hashes = []
        array_of_attributes.each_with_index do |array, i|
          hash = column_names.zip(array).to_h.with_indifferent_access
          hash[self.primary_key] = ids[i] if hash[self.primary_key].blank?
          array_of_hashes << hash
        end

        self.kafka_producers.each { |p| p.send_events(array_of_hashes) }
        results
      end
    end
  end
end
