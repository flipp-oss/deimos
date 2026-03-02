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

    class ProcString < String
      def inspect
        self.to_s
      end
    end

    source_root File.expand_path('v2/templates', __dir__)

    no_commands do
      def deimos_config
        Deimos.config
      end

      def deimos_configs
        configs = {
          producers: %i(topic_prefix disabled backend),
          schema: %i(backend registry_url user password path generated_class_path use_schema_classes
                     nest_child_schemas use_full_namespace schema_namespace_map),
          db_producer: %i(log_topics compact_topics)
        }

        response = {}
        configs.each do |group, settings|
          group_setting = deimos_config.send(group)
          next if settings.all? { |s| group_setting.default_value?(s) }

          response[group] = {}
          settings.each do |field|
            unless group_setting.default_value?(field.to_sym)
              response[group][field.to_s] = group_setting.send(field.to_sym)
            end
          end
        end
        response
      end

      def setup_configs
        configs = {}
        configs[:client_id] = if deimos_config.kafka.client_id &&
                                 deimos_config.kafka.client_id != 'phobos'
                                deimos_config.kafka.client_id
                              else
                                subclass = Rails::Application.subclasses.first
                                if subclass
                                  subclass.name.gsub('::Application', '').underscore
                                else
                                  nil
                                end
                              end
        if deimos_config.consumer_objects.any? { |c| c.max_concurrency.present? }
          configs[:concurrency] = deimos_config.consumer_objects.map(&:max_concurrency).compact.max
        end
        if deimos_config.consumer_objects.any? { |c| c.max_wait_time.present? }
          configs[:max_wait_time] = deimos_config.consumer_objects.map(&:max_wait_time).compact.max
        end
        configs.compact
      end

      def default_kafka_configs
        configs = {}
        configs['bootstrap.servers'] = deimos_config.kafka.seed_brokers.join(',')
        configs['socket.connection.setup.timeout.ms'] = deimos_config.kafka.connect_timeout * 1000
        configs['socket.timeout.ms'] = deimos_config.kafka.socket_timeout * 1000
        configs['security.protocol'] = if deimos_config.kafka.ssl.enabled
                                         'ssl'
                                       elsif deimos_config.kafka.sasl.enabled
                                         if deimos_config.kafka.sasl.enforce_ssl
                                           'sasl_ssl'
                                         else
                                           'sasl_plain'
                                         end
                                       end
        configs['ssl.ca.location'] = deimos_config.kafka.ssl.ca_cert
        configs['ssl.certificate.location'] = deimos_config.kafka.ssl.client_cert
        configs['ssl.key.location'] = deimos_config.kafka.ssl.client_cert_key
        if deimos_config.kafka.ssl.verify_hostname
          configs['ssl.endpoint.identification.algorithm'] = 'https'
        end
        configs['sasl.kerberos.principal'] = deimos_config.kafka.sasl.gssapi_principal
        configs['sasl.kerberos.keytab'] = deimos_config.kafka.sasl.gssapi_keytab
        configs['sasl.username'] = deimos_config.kafka.sasl.plain_username ||
                                   deimos_config.kafka.sasl.scram_username
        configs['sasl.password'] = deimos_config.kafka.sasl.plain_password ||
                                   deimos_config.kafka.sasl.scram_password
        configs['sasl.mechanisms'] = deimos_config.kafka.sasl.scram_mechanism
        configs['request.required.acks'] = deimos_config.producers.required_acks
        configs['message.send.max.retries'] = deimos_config.producers.max_retries
        if deimos_config.producers.retry_backoff
          configs['retry.backoff.ms'] = deimos_config.producers.retry_backoff * 1000
        end
        configs['compression.codec'] = deimos_config.producers.compression_codec
        configs.compact
      end

      def default_configs
        {
          payload_log: deimos_config.payload_log,
          reraise_errors: deimos_config.consumers.reraise_errors,
          replace_associations: deimos_config.consumers.replace_associations,
          namespace: deimos_config.producers.schema_namespace,
          use_schema_classes: deimos_config.schema.use_schema_classes
        }.compact
      end

      def consumer_configs
        deimos_config.consumer_objects.group_by(&:group_id).to_h do |group_id, consumers|
          [group_id, consumers.map do |consumer|
            kafka_configs = {}
            kafka_configs['auto.offset.reset'] = consumer.start_from_beginning ? 'earliest' : 'latest'
            unless consumer.default_value?(:session_timeout)
              kafka_configs['session.timeout.ms'] = consumer.session_timeout * 1000
            end
            unless consumer.default_value?(:offset_commit_interval)
              kafka_configs['auto.commit.interval.ms'] = consumer.offset_commit_interval * 1000
            end
            unless consumer.default_value?(:heartbeat_interval)
              kafka_configs['heartbeat.interval.ms'] = consumer.heartbeat_interval * 1000
            end
            configs = {
              kafka: kafka_configs.compact,
              topic: consumer.topic,
              consumer: ProcString.new(consumer.class_name),
              schema: consumer.schema,
              namespace: consumer.namespace,
              key_config: consumer.key_config
            }
            unless consumer.default_value?(:use_schema_classes)
              configs[:use_schema_classes] = consumer.use_schema_classes
            end
            unless consumer.default_value?(:max_db_batch_size)
              configs[:max_db_batch_size] = consumer.max_db_batch_size
            end
            unless consumer.default_value?(:bulk_import_id_column)
              configs[:bulk_import_id_column] = consumer.bulk_import_id_column
            end
            unless consumer.default_value?(:replace_associations)
              configs[:replace_associations] = consumer.replace_associations
            end
            unless consumer.default_value?(:save_associations_first)
              configs[:save_associations_first] = consumer.save_associations_first
            end
            configs[:active] = false if consumer.disabled
            configs[:each_message] = true unless consumer.delivery.to_s == 'inline_batch'
            configs
          end]
        end
      end

      def producer_configs
        deimos_config.producer_objects.map do |producer|
          {
            topic: producer.topic,
            producer_class: ProcString.new(producer.class_name),
            schema: producer.schema,
            namespace: producer.namespace || deimos_config.producers.schema_namespace,
            key_config: producer.key_config,
            use_schema_classes: producer.use_schema_classes
          }.compact
        end
      end

      def rename_consumer_methods
        deimos_config.consumer_objects.each do |consumer|
          consumer.class_name.constantize
          file = Object.const_source_location(consumer.class_name)[0]
          next unless file.to_s.include?(Rails.root.to_s)

          gsub_file(file, /([\t ]+)def consume\((\w+)(, *(\w+)?)\)/,
                    "\\1def consume_message(message)\n\\1  \\2 = message.payload\n\\1  \\4 = message.metadata")
          gsub_file(file, /([\t ]+)def consume_batch\((\w+)(, *(\w+)?)\)/,
                    "\\1def consume_batch\n\\1  \\2 = messages.payloads\n\\1  \\4 = messages.metadata")
          gsub_file(file, /def record_attributes\((\w+)\)/,
                    'def record_attributes(\\1, key)')
        end
      end

      def fix_specs
        Dir['*/**/*_spec.rb'].each do |file|
          gsub_file(file, /,\s*call_original: true/, '')
          gsub_file(file, 'Deimos::Backends::Test.sent_messages',
                    'Deimos::TestHelpers.sent_messages')
        end
      end

      def process_all_files
        template('karafka.rb.tt', 'karafka.rb', force: true)
        rename_consumer_methods
        fix_specs
        insert_into_file('Gemfile', "  gem 'karafka-testing'\n", after: "group :test do\n")
        # to avoid inserting multiple times, just in case there isn't a single group :test
        insert_into_file('Gemfile', "  gem 'karafka-testing'\n", after: /group .*test.* do\n/)
      end

    end

    desc 'Generate and update app files for version 2.0'
    # @return [void]
    def generate
      process_all_files
      say('Generation complete! You are safe to remove the existing initializer that configures Deimos.', :green)
      print_warnings
    end

    def print_warnings
      say('Note: The following settings cannot be determined by the generator:', :yellow)
      say('*  logger / phobos_logger (dynamic object, cannot be printed out)', :yellow)
      say('*  kafka.sasl.oauth_token_provider', :yellow)
      say('*  producers.max_buffer_size', :yellow)
      say('*  metrics', :yellow)
      say('*  tracer', :yellow)
      say('*  consumers.bulk_import_id_generator', :yellow)
      say('*  consumer.fatal_error', :yellow)
      say('*  consumer.backoff (only handles minimum, not maximum)', :yellow)
      say('For more information, see https://github.com/flipp-oss/deimos/blob/master/docs/UPGRADING.md', :yellow)
    end
    end
  end
end
