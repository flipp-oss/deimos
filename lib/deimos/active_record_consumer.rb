# frozen_string_literal: true

require 'deimos/consumer'

module Deimos
  # Consumer that automatically saves the payload into the database.
  class ActiveRecordConsumer < Consumer
    class << self
      # param klass [Class < ActiveRecord::Base] the class used to save to the
      # database.
      def record_class(klass)
        config[:record_class] = klass
      end
    end

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
      attrs = record_attributes(payload.with_indifferent_access)
      # don't use attributes= - bypass Rails < 5 attr_protected
      attrs.each do |k, v|
        record.send("#{k}=", v)
      end
      record.created_at ||= Time.zone.now if record.respond_to?(:created_at)
      record.updated_at ||= Time.zone.now if record.respond_to?(:updated_at)
      record.save!
    end

    # Destroy a record that received a null payload. Override if you need
    # to do something other than a straight destroy (e.g. mark as archived).
    # @param record [ActiveRecord::Base]
    def destroy_record(record)
      record&.destroy
    end

    # Override this method (with `super`) if you want to add/change the default
    # attributes set to the new/existing record.
    # @param payload [Hash]
    def record_attributes(payload)
      klass = self.class.config[:record_class]
      attributes = {}
      self.class.decoder.schema_fields.each do |field|
        column = klass.columns.find { |c| c.name == field.name }
        next if column.nil?
        next if %w(updated_at created_at).include?(field.name)

        attributes[field.name] = _coerce_field(column, payload[field.name])
      end
      attributes
    end

  private

    # @param column [ActiveRecord::ConnectionAdapters::Column]
    # @param val [Object]
    def _coerce_field(column, val)
      return nil if val.nil?

      is_integer = begin
                     val.is_a?(Integer) || (val.is_a?(String) && Integer(val))
                   rescue StandardError
                     false
                   end

      if column.type == :datetime && is_integer
        return Time.zone.strptime(val.to_s, '%s')
      end

      val
    end
  end
end
