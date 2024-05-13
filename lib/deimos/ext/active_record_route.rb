module Deimos
  class ActiveRecordRoute < Karafka::Routing::Features::Base
    module Topic
      %w(max_db_batch_size bulk_import_id_column replace_associations bulk_import_id_generator).each do |field|
        define_method(field) do |val=nil|
          @_deimos_config = {}
          return @_deimos_config[field] if val.nil?
          @_deimos_config[field] = val
        end
      end
    end
  end
end

Deimos::ActiveRecordRoute.activate
