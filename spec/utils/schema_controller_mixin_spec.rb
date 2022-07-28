# frozen_string_literal: true

require 'deimos/utils/schema_controller_mixin'
require 'deimos/schema_backends/avro_local'

RSpec.describe Deimos::Utils::SchemaControllerMixin, type: :controller do

  before(:each) do
    Deimos.configure do
      schema.backend(:avro_local)
    end
  end

  controller(ActionController::Base) do
    include Deimos::Utils::SchemaControllerMixin # rubocop:disable RSpec/DescribedClass

    request_namespace 'com.my-namespace.request'
    response_namespace 'com.my-namespace.response'
    schemas :index, :show
    schemas create: 'CreateTopic'
    schemas :update, request: 'UpdateRequest', response: 'UpdateResponse'

    # :nodoc:
    def index
      render_schema({ 'response_id' => payload[:request_id] + ' mom' })
    end

    # :nodoc:
    def show
      render_schema({ 'response_id' => payload[:request_id] + ' dad' })
    end

    # :nodoc:
    def create
      render_schema({ 'response_id' => payload[:request_id] + ' bro' })
    end

    # :nodoc:
    def update
      render_schema({ 'update_response_id' => payload[:update_request_id] + ' sis' })
    end
  end

  it 'should render the correct response for index' do
    request_backend = Deimos.schema_backend(schema: 'Index',
                                            namespace: 'com.my-namespace.request')
    response_backend = Deimos.schema_backend(schema: 'Index',
                                             namespace: 'com.my-namespace.response')
    request.content_type = 'avro/binary'
    get :index, body: request_backend.encode({ 'request_id' => 'hi' })
    expect(response_backend.decode(response.body)).to eq({ 'response_id' => 'hi mom' })
  end

  it 'should render the correct response for show' do
    request_backend = Deimos.schema_backend(schema: 'Index',
                                            namespace: 'com.my-namespace.request')
    response_backend = Deimos.schema_backend(schema: 'Index',
                                             namespace: 'com.my-namespace.response')
    request.content_type = 'avro/binary'
    get :show, params: { id: 1 }, body: request_backend.encode({ 'request_id' => 'hi' })
    expect(response_backend.decode(response.body)).to eq({ 'response_id' => 'hi dad' })
  end

  it 'should render the correct response for update' do
    request_backend = Deimos.schema_backend(schema: 'UpdateRequest',
                                            namespace: 'com.my-namespace.request')
    response_backend = Deimos.schema_backend(schema: 'UpdateResponse',
                                             namespace: 'com.my-namespace.response')
    request.content_type = 'avro/binary'
    post :update, params: { id: 1 }, body: request_backend.encode({ 'update_request_id' => 'hi' })
    expect(response_backend.decode(response.body)).to eq({ 'update_response_id' => 'hi sis' })
  end

  it 'should render the correct response for create' do
    request_backend = Deimos.schema_backend(schema: 'CreateTopic',
                                            namespace: 'com.my-namespace.request')
    response_backend = Deimos.schema_backend(schema: 'CreateTopic',
                                             namespace: 'com.my-namespace.response')
    request.content_type = 'avro/binary'
    post :create, params: { id: 1 }, body: request_backend.encode({ 'request_id' => 'hi' })
    expect(response_backend.decode(response.body)).to eq({ 'response_id' => 'hi bro' })
  end

end
