# frozen_string_literal: true

# Mock consumer
class MyConfigConsumer < Deimos::Consumer
  # :no-doc:
  def consume
  end
end

# Mock consumer 2
class MyConfigConsumer2 < Deimos::Consumer
  # :no-doc:
  def consume
  end
end

describe Deimos, 'configuration' do
  it 'should override global configurations' do
    described_class.configure do
      consumers.bulk_import_id_generator(-> { 'global' })
      consumers.replace_associations true

      consumer do
        class_name 'MyConfigConsumer'
        schema 'blah'
        topic 'blah'
        bulk_import_id_generator(-> { 'consumer' })
        replace_associations false
      end

      consumer do
        class_name 'MyConfigConsumer2'
        schema 'blah'
        topic 'blah'
      end
    end

    consumers = described_class.config.consumers
    expect(consumers.replace_associations).to eq(true)
    expect(consumers.bulk_import_id_generator.call).to eq('global')

    custom = MyConfigConsumer.config
    expect(custom[:replace_associations]).to eq(false)
    expect(custom[:bulk_import_id_generator].call).to eq('consumer')

    default = MyConfigConsumer2.config
    expect(default[:replace_associations]).to eq(true)
    expect(default[:bulk_import_id_generator].call).to eq('global')

  end
end
