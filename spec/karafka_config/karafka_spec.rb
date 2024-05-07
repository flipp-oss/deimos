RSpec.describe 'Karafka configs' do
  before(:each) do
    KarafkaApp.routes.clear
    $found_stuff = nil
  end

  let(:consumer_class) do
    Class.new(Deimos::Consumer) do
      def consume_message(message)
        $found_stuff = 'YES'
      end
    end
  end
  let(:consumer) { karafka.consumer_for('MyTopic') }

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
    expect($found_stuff).to eq('YES')
  end

end
