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
      # @param klass [Class<BasicObject>]
      # @param refetch [Boolean] if true, and we are given a hash instead of
      # a record object, refetch the record to pass into the `generate_payload`
      # method.
      # @return [void]
      def record_class(klass, refetch: true)
        config[:record_class] = klass
        config[:refetch_record] = refetch
      end

      # @param record [ActiveRecord::Base]
      # @param force_send [Boolean]
      # @return [void]
      def send_event(record, force_send: false)
        send_events([record], force_send: force_send)
      end

      # @param records [Array<ActiveRecord::Base>]
      # @param force_send [Boolean]
      # @return [void]
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
        self.post_process(records)
      end

      # Generate the payload, given a list of attributes or a record..
      # Can be overridden or added to by subclasses.
      # @param attributes [Hash]
      # @param _record [ActiveRecord::Base] May be nil if refetch_record
      # is not set.
      # @return [Hash]
      def generate_payload(attributes, _record)
        fields = self.encoder.schema_fields
        payload = attributes.stringify_keys
        payload.delete_if do |k, _|
          k.to_sym != :payload_key && !fields.map(&:name).include?(k)
        end
        return payload unless Utils::SchemaClass.use?(config.to_h)

        Utils::SchemaClass.instance(payload, config[:schema], config[:namespace])
      end

      # Query to use when polling the database with the DbPoller. Add
      # includes, joins, or wheres as necessary, or replace entirely.
      # @param time_from [Time] the time to start the query from.
      # @param time_to [Time] the time to end the query.
      # @param column_name [Symbol] the column name to look for.
      # @param min_id [Numeric] the minimum ID (i.e. all IDs must be greater
      # than this value).
      # @return [ActiveRecord::Relation]
      def poll_query(time_from:, time_to:, min_id:, column_name: :updated_at)
        klass = config[:record_class]
        table = ActiveRecord::Base.connection.quote_table_name(klass.table_name)
        column = ActiveRecord::Base.connection.quote_column_name(column_name)
        primary = ActiveRecord::Base.connection.quote_column_name(klass.primary_key)
        klass.where(
          "((#{table}.#{column} = ? AND #{table}.#{primary} > ?) \
           OR #{table}.#{column} > ?) AND #{table}.#{column} <= ?",
          time_from,
          min_id,
          time_from,
          time_to
        )
      end

      # Post process records after publishing
      # @param _records [Array<ActiveRecord::Base>]
      # @return [void]
      def post_process(_records)
      end

    end
  end
end
