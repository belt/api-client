require "spec_helper"
require "api_client"

# Load the adapter if available
if ApiClient::Backend.available?(:typhoeus)
  ApiClient::Backend.resolve(:typhoeus)
end

# Skip entire file if Typhoeus adapter not available
return unless defined?(ApiClient::Adapters::TyphoeusAdapter)

RSpec.describe ApiClient::Adapters::TyphoeusAdapter, :integration,
  if: ApiClient::Backend.available?(:typhoeus) do
  subject(:adapter) { described_class.new(config) }

  let(:config) { build(:api_client_configuration, service_uri: base_url) }

  it_behaves_like "parallel adapter"
  it_behaves_like "response normalization"

  describe "#initialize" do
    it "sets config" do
      expect(adapter.config).to eq(config)
    end

    it "configures typhoeus" do
      # Verify Typhoeus is configured (no error on init)
      expect(adapter).to be_a(described_class)
    end
  end

  describe "Hydra parallel execution" do
    it "uses Hydra for parallel requests" do
      requests = 5.times.map { {method: :get, path: "/delay/0.1"} }

      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      adapter.execute(requests)
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start

      # 5 x 0.1s should take ~0.1s with Hydra, not 0.5s
      expect(elapsed).to be < 0.3
    end
  end

  describe "body encoding" do
    it "encodes hash body as JSON" do
      responses = adapter.execute([
        {method: :post, path: "/users", body: {name: "Test"}}
      ])
      expect(responses.first.status).to eq(201)
    end

    it "passes string body as-is" do
      responses = adapter.execute([
        {method: :post, path: "/echo", body: '{"raw":"json"}'}
      ])
      expect(responses.first.status).to eq(200)
    end
  end

  describe "response normalization" do
    it "normalizes timed out responses" do
      timed_out_response = instance_double(
        Typhoeus::Response,
        timed_out?: true,
        code: 0,
        effective_url: "http://example.com/test"
      )

      hydra = instance_double(Typhoeus::Hydra)
      allow(Typhoeus::Hydra).to receive(:new).and_return(hydra)
      allow(hydra).to receive(:queue) do |req|
        req.execute_callbacks(timed_out_response) if req.respond_to?(:execute_callbacks)
      end
      allow(hydra).to receive(:run)

      result = adapter.send(:normalize_response, timed_out_response)
      expect(result).to be_a(Faraday::Response)
      expect(result.status).to eq(0)
    end

    it "normalizes connection failure responses" do
      failed_response = instance_double(
        Typhoeus::Response,
        timed_out?: false,
        code: 0,
        return_message: "Connection refused",
        effective_url: "http://example.com/test"
      )

      result = adapter.send(:normalize_response, failed_response)
      expect(result).to be_a(Faraday::Response)
      expect(result.status).to eq(0)
    end

    it "normalizes successful responses" do
      success_response = instance_double(
        Typhoeus::Response,
        timed_out?: false,
        code: 200,
        body: '{"ok":true}',
        headers: {"Content-Type" => "application/json"},
        effective_url: "http://example.com/test"
      )

      result = adapter.send(:normalize_response, success_response)
      expect(result).to be_a(Faraday::Response)
      expect(result.status).to eq(200)
      expect(result.body).to eq('{"ok":true}')
    end

    it "handles nil effective_url in timeout" do
      timed_out_response = instance_double(
        Typhoeus::Response,
        timed_out?: true,
        code: 0,
        effective_url: nil
      )

      result = adapter.send(:normalize_response, timed_out_response)
      expect(result.status).to eq(0)
    end

    it "handles nil effective_url in connection failure" do
      failed_response = instance_double(
        Typhoeus::Response,
        timed_out?: false,
        code: 0,
        return_message: "DNS resolution failed",
        effective_url: nil
      )

      result = adapter.send(:normalize_response, failed_response)
      expect(result.status).to eq(0)
    end
  end

  describe "header parsing" do
    it "parses hash headers" do
      result = adapter.send(:parse_headers, {"Content-Type" => "text/html"})
      expect(result).to eq({"Content-Type" => "text/html"})
    end

    it "parses string headers" do
      header_string = "Content-Type: application/json\r\nX-Custom: value"
      result = adapter.send(:parse_headers, header_string)
      expect(result).to eq({"Content-Type" => "application/json", "X-Custom" => "value"})
    end

    it "returns empty hash for nil headers" do
      result = adapter.send(:parse_headers, nil)
      expect(result).to eq({})
    end

    it "returns empty hash for unexpected type" do
      result = adapter.send(:parse_headers, 42)
      expect(result).to eq({})
    end
  end

  describe "empty requests" do
    it "returns empty array" do
      expect(adapter.execute([])).to eq([])
    end
  end

  describe "instrumentation" do
    it "instruments batch_start" do
      events = []
      subscriber = ApiClient::Hooks.subscribe(:batch_start) do |*args|
        events << ActiveSupport::Notifications::Event.new(*args)
      end

      adapter.execute([{method: :get, path: "/users/1"}])

      expect(events.size).to eq(1)
      expect(events.first.payload).to include(adapter: :typhoeus, count: 1)
    ensure
      ApiClient::Hooks.unsubscribe(subscriber)
    end

    it "instruments batch_complete" do
      events = []
      subscriber = ApiClient::Hooks.subscribe(:batch_complete) do |*args|
        events << ActiveSupport::Notifications::Event.new(*args)
      end

      adapter.execute([{method: :get, path: "/users/1"}])

      expect(events.size).to eq(1)
      expect(events.first.payload).to include(adapter: :typhoeus, count: 1)
    ensure
      ApiClient::Hooks.unsubscribe(subscriber)
    end
  end
end
