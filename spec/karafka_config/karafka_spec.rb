RSpec.describe 'Karafka configs' do
  before(:each) do
    KarafkaApp.routes.clear
    $found_stuff = nil
  end

  let(:consumer_class) do
    Class.new(Deimos::Consumer) do
      def consume_message(message)
        $found_stuff = message.payload
      end
    end
  end

  let(:producer_class) do
    Class.new(Deimos::Producer) do
    end
  end

  describe 'producers' do
    before(:each) do
      stub_const('MyProducer', producer_class)
    end

    it 'should work with key none' do
      KarafkaApp.routes.draw do
        topic 'MyTopic' do
          producer_class MyProducer
          schema(schema: 'MySchema',
                 namespace: 'com.my-namespace',
                 key_config: {none: :true})
        end
      end
      producer_class.publish({test_id: "id1", some_int: 5})
      expect('MyTopic').to have_sent({test_id: "id1", some_int: 5})
    end

    it 'should work with key plain' do
      KarafkaApp.routes.draw do
        topic 'MyTopic' do
          producer_class MyProducer
          schema(schema: 'MySchema',
                 namespace: 'com.my-namespace',
                 key_config: {plain: :true})
        end
      end
      producer_class.publish({test_id: "id1", some_int: 5, payload_key: 'key'})
      expect('MyTopic').to have_sent({test_id: "id1", some_int: 5}, 'key')
    end

    it 'should work with key field' do
      KarafkaApp.routes.draw do
        topic 'MyTopic' do
          producer_class MyProducer
          schema(schema: 'MySchema',
                 namespace: 'com.my-namespace',
                 key_config: {field: :test_id})
        end
      end
      producer_class.publish({test_id: "id1", some_int: 5})
      expect('MyTopic').to have_sent({test_id: "id1", some_int: 5}, 'id1')
    end

    it 'should work with key schema' do
      KarafkaApp.routes.draw do
        topic 'MyTopic' do
          producer_class MyProducer
          schema(schema: 'MySchema',
                 namespace: 'com.my-namespace',
                 key_config: {schema: 'MySchema_key'})
        end
      end
      producer_class.publish({test_id: "id1", some_int: 5, payload_key: {test_id: 'id3'}})
      expect('MyTopic').to have_sent({test_id: "id1", some_int: 5}, { test_id: 'id3'})
    end

  end

  it 'should be able to pick up a consumer' do
    stub_const('MyConsumer', consumer_class)
    KarafkaApp.routes.draw do
      topic 'MyTopic' do
        consumer MyConsumer
        schema(schema: 'MySchema',
               namespace: 'com.my-namespace',
               key_config: {field: :test_id})
      end
    end

    test_consume_message('MyTopic', {test_id: "id1", some_int: 5}, key: "id1")
    expect($found_stuff).to eq({'test_id' => "id1", 'some_int' => 5})
    $found_stuff = nil
    test_consume_message(MyConsumer, {test_id: "id1", some_int: 5}, key: "id1")
    expect($found_stuff).to eq({'test_id' => "id1", 'some_int' => 5})
  end

end
