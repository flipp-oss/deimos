# frozen_string_literal: true

module Deimos
  # Shared methods for ActiveRecord consumers
  module ActiveRecordBaseConsumer
    # Add class methods
    def self.included(base)
      base.extend(ClassMethods)
    end

    # Class methods
    module ClassMethods
      # param klass [Class < ActiveRecord::Base] the class used to save to the
      # database.
      def record_class(klass)
        config[:record_class] = klass
      end
    end

    # Create decoders
    def init_consumer
      @klass = self.class.config[:record_class]

      @converter = SchemaModelConverter.new(
        self.class.decoder.avro_schema,
        @klass
      )

      if self.class.config[:key_schema] # rubocop:disable Style/GuardClause
        @key_converter = SchemaModelConverter.new(
          self.class.key_decoder.avro_schema,
          @klass
        )
      end
    end
  end
end
