# frozen_string_literal: true

# THINGS TO REMEMBER
# logger
# fatal_error
# bulk_import_id_generator

require 'rails/generators'
require 'rails/version'

# Generates a new consumer.
module Deimos
  module Generators
    # Generator for ActiveRecord model and migration.
    class V2Generator < Rails::Generators::Base

      class << self
        attr_accessor :original_config
      end

      source_root File.expand_path('v2/templates', __dir__)

      no_commands do
        def orig_config
          self.class.original_config
        end

        def deimos_configs
          {
            producers: %i(topic_prefix disabled backend),
            schema: %i(backend registry_url user password path generated_class_path use_schema_classes
                       nest_child_schemas use_full_namespace schema_namespace_map),
            db_producer: %i(log_topics compact_topics),
          }
        end

        def setup_configs
          configs = {}
          configs[:client_id] = orig_config.kafka.client_id if orig_config.kafka.client_id
          if orig_config.consumer_objects.any? { |c| c.max_concurrency.present? }
            configs[:concurrency] = orig_config.consumer_objects.map(&:max_concurrency).compact.max
          end
          if orig_config.consumer_objects.any? { |c| c.max_wait_time.present? }
            configs[:max_wait_time] = orig_config.consumer_objects.map(&:max_wait_time).compact.max
          end
          configs.compact
        end

        def default_kafka_configs
          configs = {}
          configs["metadata.broker.list"] = orig_config.kafka.seed_brokers
          configs["socket.connection.setup.timeout.ms"] = orig_config.kafka.connect_timeout * 1000
          configs["socket.timeout.ms"] = orig_config.kafka.socket_timeout * 1000
          configs["security.protocol"] = if orig_config.kafka.ssl.enabled
                                           "ssl"
                                         elsif orig_config.kafka.sasl.enabled
                                           if orig_config.kafka.sasl.enforce_ssl
                                             "sasl_ssl"
                                           else
                                             "sasl_plain"
                                           end
                                         end
          configs["ssl.ca.pem"] = orig_config.kafka.ssl.ca_cert
          configs["ssl.certificate.pem"] = orig_config.kafka.ssl.client_cert
          configs["ssl.endpoint.identification.algorithm"] = "https" if orig_config.kafka.ssl.verify_hostname
          configs["sasl.kerberos.principal"] = orig_config.kafka.sasl.gssapi_principal
          configs["sasl.kerberos.keytab"] = orig_config.kafka.sasl.gssapi_keytab
          configs["sasl.username"] = orig_config.kafka.sasl.plain_username || orig_config.kafka.sasl.scram_password
          configs["sasl.password"] = orig_config.kafka.sasl.plain_password || orig_config.kafka.sasl.scram_password
          configs["sasl.mechanisms"] = orig_config.kafka.sasl.scram_mechanism
          configs["request.required.acks"] = orig_config.producers.required_acks
          configs["message.send.max.retries"] = orig_config.producers.max_retries
          configs["retry.backoff.ms"] = orig_config.producers.retry_backoff * 1000 if orig_config.producers.retry_backoff
          configs["compression.codec"] = orig_config.producers.compression_codec
          configs.compact
        end

        def default_configs
          {
            payload_log: orig_config.payload_log,
            reraise_errors: orig_config.consumers.reraise_errors,
            replace_associations: orig_config.consumers.replace_associations,
            namespace: orig_config.producers.schema_namespace,
            use_schema_classes: orig_config.schema.use_schema_classes
          }.compact
        end

        def consumer_configs
          orig_config.consumer_objects.map do |consumer|
            kafka_configs = {}
            kafka_configs["group.id"] = consumer.group_id
            kafka_configs["auto.offset.reset"] = consumer.start_from_beginning ? 'earliest' : 'latest'
            kafka_configs["session.timeout.ms"] = consumer.session_timeout * 1000 unless consumer.default_value?(:session_timeout)
            kafka_configs["auto.commit.interval.ms"] = consumer.offset_commit_interval * 1000 unless consumer.default_value?(:offset_commit_interval)
            kafka_configs["heartbeat.interval.ms"] = consumer.heartbeat_interval * 1000 unless consumer.default_value?(:heartbeat_interval)
            configs = {
              kafka: kafka_configs.compact,
              topic: consumer.topic,
              consumer: consumer.class_name,
              schema: consumer.schema,
              namespace: consumer.namespace,
              key_config: consumer.key_config,
            }
            configs[:use_schema_classes] = consumer.use_schema_classes unless consumer.default_value?(:use_schema_classes)
            configs[:max_db_batch_size] = consumer.max_db_batch_size unless consumer.default_value?(:max_db_batch_size)
            configs[:bulk_import_id_column] = consumer.bulk_import_id_column unless consumer.default_value?(:bulk_import_id_column)
            configs[:replace_associations] = consumer.replace_associations unless consumer.default_value?(:replace_associations)
            configs[:active] = false if consumer.disabled
            configs[:batch] = true if consumer.delivery.to_s == 'inline_batch'
            configs
          end
        end

        def producer_configs
          orig_config.producer_objects.map do |producer|
            {
              topic: producer.topic,
              producer_class: producer.class_name,
              schema: producer.schema,
              namespace: producer.namespace || orig_config.producers.schema_namespace,
              key_config: producer.key_config,
              use_schema_classes: producer.use_schema_classes
            }.compact
          end
        end

        def rename_consumer_methods
          orig_config.consumer_objects.each do |consumer|
            consumer.class_name.constantize
            file = Object.const_source_location(consumer.class_name)[0]
            puts file
            if file.to_s.include?(Rails.root.to_s)
              gsub_file(file, /([\t ]+)def consume\(.*\)/,
                        "\\1def consume_message(message)\n\\1  payload = message.payload\n\\1  metadata = message.metadata")
              gsub_file(file, /([\t ]+)def consume_batch\(.*\)/,
                        "\\1def consume_batch\n\\1  payloads = messages.payloads\n\\1  metadata = messages.metadata")
            end
          end
        end

      end

      desc 'Generate and update app files for version 2.0'
      # @return [void]
      def generate
        template('karafka.rb.tt', "karafka.rb", force: true)
        rename_consumer_methods
      end
    end
  end
end
