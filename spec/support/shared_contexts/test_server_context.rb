module TestServerHolder
  class << self
    attr_accessor :instance # standard:disable ThreadSafety/ClassAndModuleAttributes
  end
end

# Test-specific client that uses unique circuit names to prevent state pollution
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

RSpec.shared_context "with test server" do
  let(:test_server) { TestServerHolder.instance }
  let(:base_url) { test_server.base_url }
  let(:test_id) { SecureRandom.hex(4) }

  def client_for_server(**overrides)
    ApiClient::TestClient.new(service_uri: base_url, test_id: test_id, **overrides)
  end
end

RSpec.configure do |config|
  config.include_context "with test server", :integration

  # Lazy-start: only boot the test server when the first :integration spec runs.
  # Avoids starting the async/Falcon container for non-integration runs.
  config.before(:each, :integration) do
    unless TestServerHolder.instance
      require_relative "../test_server/server"
      TestServerHolder.instance = Support::TestServer.new.start
    end
    TestServerHolder.instance.clear_requests
  end

  config.after(:suite) do
    TestServerHolder.instance&.stop
  end
end
