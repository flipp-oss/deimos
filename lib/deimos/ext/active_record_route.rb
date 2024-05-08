module Deimos
  class ActiveRecordRoute < Karafka::Routing::Features::Base
    module Topic
      def active_record(max_db_batch_size: nil, bulk_import_id_column: nil,
                        replace_associations: nil, bulk_import_id_generator: nil)
        @active_record = {
          max_db_batch_size: max_db_batch_size,
          bulk_import_id_column: bulk_import_id_column,
          replace_associations: replace_associations,
          bulk_import_id_generator: bulk_import_id_generator
        }
      end
    end
  end
end

Deimos::ActiveRecordRoute.activate
