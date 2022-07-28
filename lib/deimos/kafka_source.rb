# frozen_string_literal: true

module Deimos
  # Represents an object which needs to inform Kafka when it is saved or
  # bulk imported.
  module KafkaSource
    extend ActiveSupport::Concern

    DEPRECATION_WARNING = 'The kafka_producer interface will be deprecated ' \
        'in future releases. Please use kafka_producers instead.'

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
        if self.respond_to?(:kafka_producer)
          Deimos.config.logger.warn(message: DEPRECATION_WARNING)
          return [self.kafka_producer]
        end

        raise NotImplementedError
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
        if !self.kafka_config[:import] || array_of_attributes.empty?
          return results
        end

        # This will contain an array of hashes, where each hash is the actual
        # attribute hash that created the object.
        array_of_hashes = []
        array_of_attributes.each do |array|
          array_of_hashes << column_names.zip(array).to_h.with_indifferent_access
        end
        hashes_with_id, hashes_without_id = array_of_hashes.partition { |arr| arr[:id].present? }

        self.kafka_producers.each { |p| p.send_events(hashes_with_id) }

        if hashes_without_id.any?
          if options[:on_duplicate_key_update].present? &&
             options[:on_duplicate_key_update] != [:updated_at]
            unique_columns = column_names.map(&:to_s) -
                             options[:on_duplicate_key_update].map(&:to_s) - %w(id created_at)
            records = hashes_without_id.map do |hash|
              self.where(unique_columns.map { |c| [c, hash[c]] }.to_h).first
            end
            self.kafka_producers.each { |p| p.send_events(records) }
          else
            # re-fill IDs based on what was just entered into the DB.
            last_id = if self.connection.adapter_name.downcase =~ /sqlite/
                        self.connection.select_value('select last_insert_rowid()') -
                          hashes_without_id.size + 1
                      else # mysql
                        self.connection.select_value('select LAST_INSERT_ID()')
                      end
            hashes_without_id.each_with_index do |attrs, i|
              attrs[:id] = last_id + i
            end
            self.kafka_producers.each { |p| p.send_events(hashes_without_id) }
          end
        end
        results
      end
    end
  end
end
