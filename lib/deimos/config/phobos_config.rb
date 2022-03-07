# frozen_string_literal: true

require 'active_support/core_ext/array'

module Deimos
  # Module to handle phobos.yml as well as outputting the configuration to save
  # to Phobos itself.
  module PhobosConfig
    extend ActiveSupport::Concern

    # @return [Hash]
    def to_h
      (FIELDS + [:handler]).to_h do |f|
        val = self.send(f)
        if f == :backoff && val
          [:backoff, _backoff(val)]
        elsif val.present?
          [f, val]
        end
      end
    end

    # :nodoc:
    def reset!
      super
      Phobos.configure(self.phobos_config)
    end

    # Create a hash representing the config that Phobos expects.
    # @return [Hash]
    def phobos_config
      p_config = {
        logger: Logger.new($stdout),
        custom_logger: self.phobos_logger,
        custom_kafka_logger: self.kafka.logger,
        kafka: {
          client_id: self.kafka.client_id,
          connect_timeout: self.kafka.connect_timeout,
          socket_timeout: self.kafka.socket_timeout,
          ssl_verify_hostname: self.kafka.ssl.verify_hostname,
          seed_brokers: Array.wrap(self.kafka.seed_brokers)
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
        backoff: _backoff(self.consumers.backoff.to_a)
      }

      p_config[:listeners] = self.consumer_objects.map do |consumer|
        next nil if consumer.disabled

        hash = consumer.to_h.reject do |k, _|
          %i(class_name schema namespace key_config backoff disabled).include?(k)
        end
        hash = hash.to_h { |k, v| [k, v.is_a?(Symbol) ? v.to_s : v] }
        hash[:handler] = consumer.class_name
        if consumer.backoff
          hash[:backoff] = _backoff(consumer.backoff.to_a)
        end
        hash
      end
      p_config[:listeners].compact!

      if self.kafka.ssl.enabled
        %w(ca_cert client_cert client_cert_key).each do |key|
          next if self.kafka.ssl.send(key).blank?

          p_config[:kafka]["ssl_#{key}".to_sym] = ssl_var_contents(self.kafka.ssl.send(key))
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
      pconfig = YAML.load(ERB.new(File.read(File.expand_path(file))).result). # rubocop:disable Security/YAMLLoad
        with_indifferent_access
      self.logger&.warn('phobos.yml is deprecated - use direct configuration instead.')
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

  private

    # @param values [Array<Integer>]
    # @return [Hash<Integer>]
    def _backoff(values)
      {
        min_ms: values[0],
        max_ms: values[-1]
      }
    end
  end
end
