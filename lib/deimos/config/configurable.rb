require 'active_support/concern'

# Features
# config.foo.bar.baz = 5
# Default values
# Default values defined with blocks (+ accessing config)
# config.foo.bar do
#   baz 5
#   spam 10
# end


module Deimos

  # Module to allow configuration. Loosely based off of the dry-configuration
  # gem but with several advantages:
  # - Works with Ruby 2.3.
  # - More succinct syntax using method_missing so you do not need to write
  #   "config.whatever" and can just write "whatever".
  # - Allows for arrays of configurations:
  #   Deimos.configure do |config|
  #     config.producer do
  #       class_name 'MyProducer'
  #       topic 'MyTopic'
  #     end
  #   end
  # - Allows to call `configure` multiple times without crashing.
  module Configurable
    extend ActiveSupport::Concern

    # Class that defines and keeps the configuration values.
    class ConfigStruct

      # @param name [String]
      def initialize(name)
        @name = name
        @config = {}
        @defaults = {}
        @setting_objects = {}
        @setting_templates = {}
      end

      # Reset config back to default values.
      def reset!
        @setting_objects = @setting_templates.map { |k, _| [k, []]}.to_h
        @config.each do |k, v|
          if v.is_a?(ConfigStruct)
            v.reset!
          else
            @config[k] = @defaults[k]
          end
        end
      end

      # :nodoc:
      def inspect
        "#{@name}: #{@config.inspect} #{@setting_objects.inspect}"
      end

      # @return [Hash]
      def to_h
        @config.to_h
      end

      # :nodoc:
      def clone
        new_config = super
        new_config.setting_objects = new_config.setting_objects.clone
        new_config.config = new_config.config.clone
        new_config
      end

      # Define a setting template for an array of objects via a block:
      #   setting_object :producer do
      #     setting :topic
      #     setting :class_name
      #   end
      # This will create the `producer` method to define these values as well
      # as the `producer_objects` method to retrieve them.
      # @param name [Symbol]
      def setting_object(name, &block)
        new_config = ConfigStruct.new("#{@name}.#{name}")
        @setting_objects[name] = []
        @setting_templates[name] = new_config
        new_config.instance_eval(&block)
      end

      # Define a setting with the given name.
      # @param name [Symbol]
      # @default_value [Object]
      def setting(name, default_value=nil, &block)
        if block_given?
          # Create a nested setting
          new_config = ConfigStruct.new("#{@name}.#{name}")
          @config[name] = new_config
          new_config.instance_eval(&block)
        else
          @defaults[name] = default_value
          @config[name] = default_value
        end
      end

      # :nodoc:
      def respond_to_missing?(method, include_all=true)
        method = method.to_s.sub(/=$/, '')
        method.ends_with?('objects') ||
          @setting_templates.key?(method.to_sym) ||
          @config.key?(method.to_sym) ||
          super
      end

      # :nodoc:
      def method_missing(method, *args, &block)

        # Return the list of setting objects with the given name
        if method.to_s.end_with?('objects')
          key = method.to_s.sub('_objects', '').to_sym
          return @setting_objects[key]
        end

        # Define a new setting object with the given name
        if @setting_templates.key?(method) && block_given?
          new_config = @setting_templates[method].clone
          new_config.instance_eval(&block)
          @setting_objects[method] << new_config
          return
        end

        # Use method_missing to set values, e.g.
        # config.foo.bar do
        #   baz 5
        #   spam "hi mom"
        # end
        if block_given?
          if @config[method].is_a?(ConfigStruct)
            @config[method].instance_eval(&block)
          else
            raise "Block called for #{method} but it is not a nested config!"
          end
        end

        method = method.to_s.sub(/=$/, '').to_sym
        return super unless @config.key?(method)
        if args.length.positive?
          # Set the value
          @config[method] = args[0]
        else
          # Get the value
          @config[method]
        end
      end

      protected

      # Only for the clone method
      attr_accessor :config, :setting_objects

    end

    class_methods do

      # Pass the configuration into a block.
      def configure(&block)
        config.instance_eval(&block)
      end

      # @return [ConfigStruct]
      def config
        @config ||= ConfigStruct.new('config')
      end
    end

  end
end
