# frozen_string_literal: true

require 'deimos/active_record_base_consumer'
require 'deimos/consumer'
require 'deimos/schema_model_converter'

module Deimos
  # Consumer that automatically saves the payload into the database.
  class ActiveRecordConsumer < Consumer
    include ActiveRecordBaseConsumer

    # Create new consumer
    def initialize
      init_consumer

      super
    end

    # :nodoc:
    def consume(payload, metadata)
      key = metadata.with_indifferent_access[:key]
      record = @klass.unscoped.where(@klass.primary_key => key).first
      if payload.nil?
        destroy_record(record)
        return
      end
      record ||= @klass.new
      attrs = record_attributes(payload.with_indifferent_access)
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

    # Override this method (with `super`) if you want to add/change the default
    # attributes set to the new/existing record.
    # @param payload [Hash]
    def record_attributes(payload)
      @converter.convert(payload)
    end
  end
end
