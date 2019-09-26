# frozen_string_literal: true

module Deimos
  module ActiveRecord
    # Consumption methods
    module MessageConsumption
      # :nodoc:
      def consume(payload, metadata)
        key = metadata.with_indifferent_access[:key]
        record = @klass.unscoped.where(@klass.primary_key => key).first
        if payload.nil?
          destroy_record(record)
          return
        end
        record ||= @klass.new
        attrs = record_attributes(key, payload.with_indifferent_access) #TODO: This is a breaking change. Arg order changed!!
        # don't use attributes= - bypass Rails < 5 attr_protected
        attrs.each do |k, v|
          record.send("#{k}=", v)
        end
        record[@klass.primary_key] = key
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
    end
  end
end