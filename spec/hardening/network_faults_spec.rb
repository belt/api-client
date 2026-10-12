require "spec_helper"
require "api_client"

RSpec.describe "Network fault handling" do
  let(:service_uri) { "https://network-fault-#{SecureRandom.hex(4)}.example.test" }
  let(:client) { ApiClient::Base.new(service_uri: service_uri, retry: {max: 0}) }

  describe "transport failures" do
    it "raises a connection error injected at the HTTP boundary" do
      stub_request(:get, "#{service_uri}/health")
        .to_raise(Faraday::ConnectionFailed.new("simulated connection refusal"))

      expect { client.get("/health") }.to raise_error(Faraday::ConnectionFailed, /simulated connection refusal/)
    end

    it "raises a timeout injected at the HTTP boundary" do
      stub_request(:get, "#{service_uri}/health")
        .to_raise(Faraday::TimeoutError.new("simulated read timeout"))

      expect { client.get("/health") }.to raise_error(Faraday::TimeoutError, /simulated read timeout/)
    end

    it "retries a transient connection failure the configured number of times" do
      retrying_client = ApiClient::Base.new(
        service_uri: service_uri,
        retry: {max: 2, interval: 0.01, interval_randomness: 0}
      )
      request = stub_request(:get, "#{service_uri}/health")
        .to_raise(Faraday::ConnectionFailed.new("simulated reset"))

      expect { retrying_client.get("/health") }.to raise_error(Faraday::ConnectionFailed)
      expect(request).to have_been_requested.times(3)
    end
  end

  describe "circuit breaker under injected failures" do
    it "opens after repeated failures and rejects subsequent requests" do # rubocop:disable RSpec/ExampleLength,RSpec/MultipleExpectations
      client = ApiClient::Base.new(
        service_uri: service_uri,
        retry: {max: 0},
        circuit: {threshold: 2, cool_off: 60}
      )
      request = stub_request(:get, "#{service_uri}/health")
        .to_raise(Faraday::ConnectionFailed.new("simulated reset"))

      2.times do
        client.get("/health")
      rescue Faraday::ConnectionFailed
        nil
      end

      expect(client.circuit_open?).to be true
      expect { client.get("/health") }.to raise_error(ApiClient::CircuitOpenError)
      expect(request).to have_been_requested.times(2)
    end
  end
end
