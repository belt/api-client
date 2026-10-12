require "rack"
require_relative "../mock_api/router"

module MockApiHolder
  class << self
    attr_accessor :instance # standard:disable ThreadSafety/ClassAndModuleAttributes
  end
end

module ApiClient
  class TestClient < Base
    def initialize(test_id: nil, **overrides)
      @test_id = test_id || SecureRandom.hex(4)
      super(**overrides)
    end

    private

    def build_circuit_name
      uri = URI.parse(@config.service_uri)
      "api_client:#{uri.host}:test-#{@test_id}"
    end
  end
end

RSpec.shared_context "with mock API" do
  let(:base_url) { MockApiHolder.instance.base_url }
  let(:test_id) { SecureRandom.hex(4) }

  def client_for_mock_api(**overrides)
    ApiClient::TestClient.new(service_uri: base_url, test_id: test_id, **overrides)
  end
end

RSpec.configure do |config|
  config.include_context "with mock API", :integration

  config.before(:each, :integration) do
    MockApiHolder.instance = Support::MockApi.new
    mock_api = MockApiHolder.instance
    stub_request(:any, %r{\A#{Regexp.escape(mock_api.base_url)}/}).to_return do |request|
      mock_api.call(request)
    end
  end
end
