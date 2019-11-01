describe Deimos do

  it 'should configure correctly' do
    class MyProducer < Deimos::Producer

    end

    # Deimos.configure do |config|
    #   config.kafka.client_id = 'foo'
    #   config.kafka.connect_timeout = 'foo'
    #   config.logger = Logger.new('/tmp/file.txt')
    #   config.schema.path = '/my/path'
    #   config.producer MyProducer do
    #     topic 'MyTopic'
    #     schema 'MySchema'
    #     namespace 'MyNamespace'
    #     key_config plain: true
    #   end
    # end
  end

end
