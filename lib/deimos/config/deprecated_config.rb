module Deimos
  # Module to handle deprecated configuration methods (e.g. phobos.yml)
  # as well as outputting the configuration to save to Phobos itself.
  module DeprecatedConfig
    extend ActiveSupport::Concern

    # @return [Hash]
    def to_h
      (FIELDS + [:handler]).map { |f|
        val = self.send(f)
        if f == :backoff && val
          [:backoff, {
            min_ms: val[0],
            max_ms: val[-1]
          }]
        elsif val.present?
          [f, val]
        end
        }.to_h
    end

    # Deprecate an old message indicating that the new message should be called.
    # @param old_message [String]
    # @param new_message [String]
    def self.deprecate(old_message, new_message)
      define_method("#{old_message}=") do |*args|
        return super(*args) if self != Deimos.config
        Deimos.config.logger&.warn("config.#{old_message}= is deprecated - use config.#{new_message}=")
        obj = self
        messages = new_message.split('.')
        messages[0..-2].each do |message|
          obj = obj.send(message)
        end
        obj.send("#{messages[-1]}=", args[0])
      end

      define_method(old_message) do |*args|
        return super(*args) if self != Deimos.config
        Deimos.config.logger&.warn("config.#{old_message} is deprecated - use config.#{new_message}")
        obj = self
        messages = new_message.split('.')
        messages[0..-2].each do |message|
          obj = obj.send(message)
        end
        obj.send(messages[-1], *args)
      end
    end

    deprecate 'kafka_logger', 'kafka.logger'
    deprecate 'reraise_consumer_errors', 'consumers.reraise_errors'
    deprecate 'schema_registry_url', 'schema.registry_url'
    deprecate 'seed_broker', 'kafka.seed_brokers'
    deprecate 'schema_path', 'schema.path'
    deprecate 'producer_schema_namespace', 'producers.schema_namespace'
    deprecate 'producer_topic_prefix', 'producers.topic_prefix'
    deprecate 'disable_producers', 'producers.disabled'
    deprecate 'ssl_enabled', 'kafka.ssl.enabled'
    deprecate 'ssl_ca_cert', 'kafka.ssl.ca_cert'
    deprecate 'ssl_client_cert', 'kafka.ssl.client_cert'
    deprecate 'ssl_client_cert_key', 'kafka.ssl.client_cert_key'
    deprecate 'publish_backend', 'producers.backend'
    deprecate 'report_lag', 'consumers.report_lag'

    # :nodoc:
    def reset!
      super
      Phobos.configure(self.phobos_config)
    end

    # Create a hash representing the config that Phobos expects.
    # @return [Hash]
    def phobos_config
      p_config = {
        logger: Logger.new(STDOUT),
        custom_logger: self.phobos_logger,
        custom_kafka_logger: self.kafka.logger,
        kafka: {
          client_id: self.kafka.client_id,
          connect_timeout: self.kafka.connect_timeout,
          socket_timeout: self.kafka.socket_timeout
        },
        producer: {
          ack_timeout: self.producers.ack_timeout,
          required_acks: self.producers.required_acks,
          max_retries: self.producers.max_retries,
          retry_backoff: self.producers.retry_backoff,
          max_buffer_size: self.producers.max_buffer_size,
          max_buffer_bytesize: self.producers.max_buffer_bytesize,
          compression_codec: self.producers.compression_codec,
          compression_threshold: self.producers.compression_threshold,
          max_queue_size: self.producers.max_queue_size,
          delivery_threshold: self.producers.delivery_threshold,
          delivery_interval: self.producers.delivery_interval
        },
        consumer: {
          session_timeout: self.consumers.session_timeout,
          offset_commit_interval: self.consumers.offset_commit_interval,
          offset_commit_threshold: self.consumers.offset_commit_threshold,
          heartbeat_interval: self.consumers.heartbeat_interval
        },
        backoff: {
          min_ms: self.consumers.backoff.to_a[0],
          max_ms: self.consumers.backoff.to_a[-1]
        },
      }

      p_config[:listeners] = self.consumer_objects.map do |consumer|
        hash = consumer.to_h.reject do |k, _|
          %i(class_name schema namespace key_config backoff).include?(k)
        end
        hash = hash.map { |k, v| [k, v.is_a?(Symbol) ? v.to_s : v]}.to_h
        hash[:handler] = consumer.class_name
        if consumer.backoff
          hash[:backoff] = {
            min_ms: consumer.backoff.to_a[0],
            max_ms: consumer.backoff.to_a[-1]
        }
        end
        hash
      end

      if self.kafka.ssl.enabled
        %w(ca_cert client_cert client_cert_key).each do |key|
          next if self.kafka.ssl.send(key).blank?

          p_config[:kafka][key.to_sym] = ssl_var_contents(self.kafka.ssl.send(key))
        end
      end
      p_config
    end

    # @param key [String]
    # @return [String]
    def ssl_var_contents(key)
      File.exist?(key) ? File.read(key) : key
    end

    # Legacy method to parse Phobos config file
    def phobos_config_file=(file)
      self.logger&.warn("phobos.yml is deprecated - use direct configuration instead.")
      pconfig = YAML.load(ERB.new(File.read(File.expand_path(file))).result).
        with_indifferent_access
      pconfig[:kafka].each do |k, v|
        if k.starts_with?('ssl')
          k = k.sub('ssl_', '')
          self.kafka.ssl.send("#{k}=", v)
        else
          self.kafka.send("#{k}=", v)
        end
      end
      pconfig[:producer].each do |k, v|
        self.producers.send("#{k}=", v)
      end
      pconfig[:consumer].each do |k, v|
        self.consumers.send("#{k}=", v)
      end
      self.consumers.backoff = pconfig[:backoff][:min_ms]..pconfig[:backoff][:max_ms]
      pconfig[:listeners].each do |listener_hash|
        self.consumer do
          listener_hash.each do |k, v|
            k = 'class_name' if k == 'handler'
            send(k, v)
          end
        end
      end
    end
  end
end
