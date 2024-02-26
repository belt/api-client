require "spec_helper"
require "api_client"

# Load the adapter if available
if ApiClient::Backend.available?(:concurrent)
  ApiClient::Backend.resolve(:concurrent)
end

RSpec.describe ApiClient::Adapters::ConcurrentAdapter, :integration,
  if: ApiClient::Backend.available?(:concurrent) do
  subject(:adapter) { described_class.new(config) }

  let(:config) { build(:api_client_configuration, service_uri: base_url) }

  it_behaves_like "parallel adapter"
  it_behaves_like "response normalization"

  describe "#initialize" do
    it "sets config" do
      expect(adapter.config).to eq(config)
    end

    it "builds connection" do
      expect(adapter.connection).to be_a(Faraday::Connection)
    end
  end

  describe "connection pooling" do
    context "with pooling enabled (default)" do
      it "uses ConnectionPool internally" do
        pool = adapter.instance_variable_get(:@pool)
        expect(pool).to be_a(ConnectionPool)
      end
    end

    context "with pooling disabled" do
      let(:config) do
        build(:api_client_configuration, service_uri: base_url).tap do |c|
          c.pool_config.enabled = false
        end
      end

      it "uses NullPool internally" do
        pool = adapter.instance_variable_get(:@pool)
        expect(pool).to be_a(ApiClient::Concerns::NullPool)
      end

      it "still executes requests" do
        responses = adapter.execute([{method: :get, path: "/health"}])
        expect(responses.first.status).to eq(200)
      end
    end
  end

  describe "thread pool execution" do
    it "uses Concurrent::Future" do
      # Verify parallel execution by timing
      requests = 3.times.map { {method: :get, path: "/delay/0.1"} }

      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      adapter.execute(requests)
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start

      expect(elapsed).to be < 0.25 # Should be ~0.1s if parallel
    end
  end
end
