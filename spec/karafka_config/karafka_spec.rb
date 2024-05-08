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

  it 'should be able to test a producer' do
    stub_const('MyProducer', producer_class)
    Deimos.configure do
      producer do
        class_name 'MyProducer'
        topic 'MyTopic'
        schema 'MySchema'
        namespace 'com.my-namespace'
        key_config({field: :test_id})
      end
    end
    producer_class.publish({test_id: "id1", some_int: 5})
    expect('MyTopic').to have_sent({test_id: "id1", some_int: 5}, {'test_id' => 'id1'})
  end

  it 'should be able to pick up a consumer' do
    stub_const('MyConsumer', consumer_class)
    KarafkaApp.routes.draw do
      topic 'MyTopic' do
        Deimos.route(self, MyConsumer,
                     schema: 'MySchema',
                     namespace: 'com.my-namespace',
                     key_config: {field: :test_id})
      end
    end

    test_consume_message('MyTopic', {test_id: "id1", some_int: 5}, key: {"test_id": "id1"})
    expect($found_stuff).to eq({'test_id' => "id1", 'some_int' => 5})
    $found_stuff = nil
    test_consume_message(MyConsumer, {test_id: "id1", some_int: 5}, key: {"test_id": "id1"})
    expect($found_stuff).to eq({'test_id' => "id1", 'some_int' => 5})
  end

end
