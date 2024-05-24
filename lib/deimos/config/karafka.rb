module Deimos
  module KarafkaConfig
    class << self
      def configure_karafka(config)
      end

      def configure_setup(config)
        Karafka::App.routes.clear
        Karafka::App.setup do |cfg|
          cfg.logger = config.logger if config.logger
          cfg.client_id = config.kafka.client_id if config.kafka.client_id
          if config.consumer_objects.any? { |c| c.max_concurrency.present? }
            cfg.concurrency = config.consumer_objects.map(&:max_concurrency).compact.max
          end
          if config.consumer_objects.any? { |c| c.max_wait_time.present? }
            cfg.max_wait_time = config.consumer_objects.map(&:max_wait_time).compact.max
          end
        end
      end

      def configure_defaults(config)
        configs = {}
        configs["metadata.broker.list"] = config.kafka.seed_brokers
        configs["socket.connection.setup.timeout.ms"] = config.kafka.connect_timeout * 1000
        configs["socket.timeout.ms"] = config.kafka.socket_timeout * 1000
        configs["security.protocol"] = if config.kafka.ssl.enabled
                                         "ssl"
                                       elsif config.kafka.sasl.enabled
                                         if config.kafka.sasl.enforce_ssl
                                           "sasl_ssl"
                                         else
                                           "sasl_plain"
                                         end
                                       end
        configs["ssl.ca.pem"] = config.kafka.ssl.ca_cert
        configs["ssl.certificate.pem"] = config.kafka.ssl.client_cert
        configs["ssl.endpoint.identification.algorithm"] = "https" if config.kafka.ssl.verify_hostname
        configs["sasl.kerberos.principal"] = config.kafka.sasl.gssapi_principal
        configs["sasl.kerberos.keytab"] = config.kafka.sasl.gssapi_keytab
        configs["sasl.username"] = config.kafka.sasl.plain_username || config.kafka.sasl.scram_password
        configs["sasl.password"] = config.kafka.sasl.plain_password || config.kafka.sasl.scram_password
        configs["sasl.mechanisms"] = config.kafka.sasl.scram_mechanism
        configs["request.required.acks"] = config.producers.required_acks
        configs["message.send.max.retries"] = config.producers.max_retries
        configs["retry.backoff.ms"] = config.producers.retry_backoff * 1000 if config.producers.retry_backoff
        configs["compression.codec"] = config.producers.compression_codec
        Karafka::App.routes.draw do
          defaults do
            payload_log(config.payload_log)
            reraise_errors(config.consumers.reraise_errors) unless config.consumers.reraise_errors.nil?
            fatal_error(config.consumers.fatal_error) if config.consumers.fatal_error
            bulk_import_id_generator(config.consumers.bulk_import_id_generator) if config.consumers.bulk_import_id_generator
            replace_associations(config.consumers.replace_associations) unless config.consumers.replace_associations.nil?
            schema(config.producers.schema_namespace) if config.producers.schema_namespace
            use_schema_classes(config.schema.use_schema_classes) unless config.schema.use_schema_classes.nil?
            kafka(**configs.compact)
          end
        end
      end

      def configure_producers(config)
        config.producer_objects.each do |producer|
          Karafka::App.routes.draw do
            topic producer.topic do
              producer_class(producer.class_name.constantize)
              schema(producer.schema)
              namespace(producer.namespace || config.producers.schema_namespace)
              key_config(producer.key_config)
              use_schema_classes(producer.use_schema_classes)
            end
          end
        end
      end

      def configure_consumers(config)
        config.consumer_objects.each do |consumer|
          klass = consumer.class_name.constantize
          configs = {}
          configs["group.id"] = consumer.group_id
          configs["auto.offset.reset"] = consumer.start_from_beginning ? 'earliest' : 'latest'
          configs["session.timeout.ms"] = consumer.session_timeout * 1000 if consumer.session_timeout
          configs["auto.commit.interval.ms"] = consumer.offset_commit_interval * 1000 if consumer.offset_commit_interval
          configs["heartbeat.interval.ms"] = consumer.heartbeat_interval * 1000 if consumer.heartbeat_interval

          Karafka::App.routes.draw do
            topic consumer.topic do
              consumer(klass)
              schema(consumer.schema)
              namespace(consumer.namespace)
              use_schema_classes(consumer.use_schema_classes)
              max_db_batch_size(consumer.max_db_batch_size)
              bulk_import_id_column(consumer.bulk_import_id_column)
              replace_associations(consumer.replace_associations)
              bulk_import_id_generator(consumer.bulk_import_id_generator)
              key_config(consumer.key_config)
              active(!consumer.disabled)
              batch(true) if consumer.delivery.to_s == 'inline_batch'
              kafka(**configs.compact)
            end

          end
        end
      end


    end
  end
end
