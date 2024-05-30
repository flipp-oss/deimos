module Deimos
  class ConsumerRoute < Karafka::Routing::Features::Base
    module Topic

      FIELDS = %i(max_db_batch_size
                  bulk_import_id_column
                  replace_associations
                  bulk_import_id_generator
                  each_message
                  reraise_errors
                  fatal_error
                  disabled
      )
      Config = Struct.new(*FIELDS, keyword_init: true)

      FIELDS.each do |field|
        define_method(field) do |val=Karafka::Routing::Default.new(nil)|
          @deimos_config ||= Config.new(
            bulk_import_id_column: :bulk_import_id,
            replace_associations: true,
            each_message: false,
            bulk_import_id_generator: proc { SecureRandom.uuid },
            fatal_error: proc { false }
          )
          unless val.is_a?(Karafka::Routing::Default)
            @deimos_config.public_send("#{field}=", val)
          end
          @deimos_config[field]
        end
      end
    end
  end
end

Deimos::ConsumerRoute.activate
