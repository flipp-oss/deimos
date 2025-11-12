# frozen_string_literal: true

# This monkey patch was provided by Maciej, the maintainer of Karafka. This allows
# configs to override each other on a more granular basis rather than each `configure` call
# blowing away all fields. It also supports multiple default blocks.
#
# Unfortunately this can't be merged into Karafka as of now because it will be a major breaking
# change. As a compromise, it has been added to the test coverage of Karafka to ensure that
# other changes don't break this.
# https://github.com/karafka/karafka/issues/2344
class Matcher
  def initialize
    @applications = []
  end

  def replay_on(topic_node)
    @applications.each do |method, kwargs|
      if method == :kafka
        topic_node.kafka = kwargs.is_a?(Array) ? kwargs[0] : kwargs
        next
      end
      if kwargs.is_a?(Hash)
        ref = topic_node.public_send(method)

        kwargs.each do |arg, val|
          if ref.respond_to?("#{arg}=")
            ref.public_send("#{arg}=", val)
          else
            if ref.respond_to?(:details)
              ref.details.merge!(kwargs)
            elsif ref.is_a?(Hash)
              ref.merge!(kwargs)
            else
              raise 'No idea if such case exists, if so, similar handling as config'
            end
          end
        end
      end

      if kwargs.is_a?(Array) && kwargs.size == 1
        if topic_node.respond_to?("#{method}=")
          topic_node.public_send(:"#{method}=", kwargs.first)
        else
          topic_node.public_send(method, *kwargs)
        end
      end
    end
  end

  def method_missing(m, *args, **kwargs)
    @applications << if args.empty?
      [m, kwargs]
                     else
      [m, args]
                     end
  end
end

DEFAULTS = Matcher.new

module Builder
  def defaults(&block)
    DEFAULTS.instance_eval(&block) if block
  end
end

module ConsumerGroup
  def topic=(name, &block)
    k = Matcher.new
    t = super(name)
    k.instance_eval(&block) if block
    DEFAULTS.replay_on(t)
    k.replay_on(t)
  end
end

Karafka::Routing::Builder.prepend(Builder)
Karafka::Routing::ConsumerGroup.prepend(ConsumerGroup)
