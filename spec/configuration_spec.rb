describe Deimos::Configuration do

  it 'should configure correctly' do
    Deimos.configure do |config|
      config.kafka.client_id = 'foo'
      config.kafka.connect_timeout = 'foo'
    end
  end

end
