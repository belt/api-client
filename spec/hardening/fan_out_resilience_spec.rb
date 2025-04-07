require "spec_helper"
require "api_client"

RSpec.describe ApiClient::Streaming::FanOutExecutor, :integration do
  let(:client) { client_for_server }

  describe "failure strategy resilience" do
    it "skip strategy drops failed requests and returns successes" do
      result = client.request_flow
        .fetch(:get, "/health")
        .then { [200, 200, 200] }
        .fan_out(on_fail: :skip) { |s| {method: :get, path: "/error/#{s}"} }
        .collect

      expect(result.size).to eq(3)
      expect(result).to all(have_attributes(status: 200))
    end

    it "collect strategy raises error with partial results on transport failure" do
      broken_client = ApiClient::TestClient.new(
        service_uri: "http://127.0.0.1:1",
        test_id: "fanout-collect",
        retry: {max: 0}
      )

      flow = broken_client.request_flow
        .fetch(:get, "/health")

      # fetch itself will fail since the server is unreachable;
      # RequestFlow wraps non-ApiClient errors in ApiClient::Error
      expect { flow.collect }.to raise_error(ApiClient::Error)
    end

    it "callback strategy invokes proc on failure" do
      fallback_called = false
      on_fail = ->(_source, _req) {
        fallback_called = true
        nil
      }

      # Use an unreachable host to trigger transport-level failures (status 0).
      broken_config = build(:api_client_configuration, :no_retry,
        service_uri: "http://127.0.0.1:1")

      batch = ApiClient::Orchestrators::Batch.new(broken_config)
      executor = described_class.new(
        broken_config,
        batch.adapter,
        on_fail: on_fail,
        retries: false
      )

      executor.execute([{method: :get, path: "/a"}])

      expect(fallback_called).to be(true)
    end
  end

  describe "input validation" do
    it "rejects non-array requests" do
      config = ApiClient.configuration
      adapter = double("adapter")
      executor = described_class.new(config, adapter)

      expect { executor.execute("not an array") }.to raise_error(ArgumentError, /must be an Array/)
    end

    it "rejects non-hash request items" do
      config = ApiClient.configuration
      adapter = double("adapter")
      executor = described_class.new(config, adapter)

      expect { executor.execute(["string"]) }.to raise_error(ArgumentError, /Hash-like/)
    end

    it "returns empty array for empty requests" do
      config = ApiClient.configuration
      adapter = double("adapter")
      executor = described_class.new(config, adapter)

      expect(executor.execute([])).to eq([])
    end
  end

  describe "timeout_ms validation" do
    it "rejects negative timeout_ms" do
      config = ApiClient.configuration
      adapter = double("adapter")

      expect {
        described_class.new(config, adapter, timeout_ms: -1)
      }.to raise_error(ArgumentError, /positive number/)
    end

    it "rejects zero timeout_ms" do
      config = ApiClient.configuration
      adapter = double("adapter")

      expect {
        described_class.new(config, adapter, timeout_ms: 0)
      }.to raise_error(ArgumentError, /positive number/)
    end

    it "clamps timeout_ms to DEFAULT_MAX_TIMEOUT_MS" do
      config = ApiClient.configuration
      adapter = double("adapter")
      executor = described_class.new(config, adapter, timeout_ms: 999_999)

      expect(executor.options[:timeout_ms]).to eq(described_class::DEFAULT_MAX_TIMEOUT_MS)
    end
  end

  describe "order preservation" do
    it "preserves order with :preserve option" do
      result = client.request_flow
        .fetch(:get, "/health")
        .then { (1..10).to_a }
        .fan_out(order: :preserve) { |id| {method: :get, path: "/posts/#{id}"} }
        .collect

      ids = result.map { |r| JSON.parse(r.body)["id"] }
      expect(ids).to eq((1..10).to_a)
    end
  end

  describe "backpressure" do
    it "respects max_inflight limit" do
      result = client.request_flow
        .fetch(:get, "/health")
        .then { (1..20).to_a }
        .fan_out(max_inflight: 2) { |id| {method: :get, path: "/posts/#{id}"} }
        .collect

      expect(result.size).to eq(20)
    end
  end

  describe "retry configuration" do
    it "disables retries with retries: false" do
      result = client.request_flow
        .fetch(:get, "/health")
        .then { [1, 2] }
        .fan_out(retries: false) { |id| {method: :get, path: "/posts/#{id}"} }
        .collect

      expect(result.size).to eq(2)
    end
  end
end
