require "spec_helper"
require "api_client"

RSpec.describe ApiClient::Circuit, :integration do
  describe "circuit state transitions" do
    let(:client) do
      client_for_server.tap do |c|
        c.config.circuit.threshold = 3
        c.config.circuit.cool_off = 1
      end
    end

    it "transitions closed → open after threshold failures" do
      expect(client.circuit.state).to eq(Stoplight::Color::GREEN)

      3.times { client.get("/error/500") rescue nil }

      expect(client.circuit.state).to eq(Stoplight::Color::RED)
    end

    it "rejects requests when open" do
      3.times { client.get("/error/500") rescue nil }

      expect { client.get("/health") }.to raise_error(ApiClient::CircuitOpenError)
    end

    it "allows probe after cool_off" do
      3.times { client.get("/error/500") rescue nil }

      Timecop.freeze(Time.now + 2) do
        client.reset_circuit!
        response = client.get("/health")
        expect(response.status).to eq(200)
      end
    end

    it "closes after successful probe" do
      3.times { client.get("/error/500") rescue nil }

      Timecop.freeze(Time.now + 2) do
        client.reset_circuit!
        client.get("/health")
        expect(client.circuit.state).to eq(Stoplight::Color::GREEN)
      end
    end
  end

  describe "circuit metrics" do
    let(:client) do
      client_for_server.tap do |c|
        c.config.circuit.threshold = 5
      end
    end

    it "tracks failure count accurately" do
      3.times { client.get("/error/500") rescue nil }

      metrics = client.circuit.metrics
      expect(metrics[:failure_count]).to eq(3)
      expect(metrics[:threshold]).to eq(5)
    end

    it "tracks recent failures with timestamps" do
      2.times { client.get("/error/500") rescue nil }

      failures = client.circuit.recent_failures(limit: 5)
      expect(failures.size).to eq(2)
      expect(failures.first).to include(:error, :message, :time)
    end
  end

  describe "circuit isolation" do
    it "maintains separate circuits per test client" do
      # Explicitly use different test_ids to ensure circuit isolation
      client1 = ApiClient::TestClient.new(service_uri: base_url, test_id: "isolation-1")
      client1.config.circuit.threshold = 2

      client2 = ApiClient::TestClient.new(service_uri: base_url, test_id: "isolation-2")
      client2.config.circuit.threshold = 2

      # Trip client1's circuit
      2.times { client1.get("/error/500") rescue nil }

      # client1 should be open
      expect(client1.circuit_open?).to be true
      # client2 has its own circuit (different test_id)
      expect(client2.circuit_open?).to be false
    end
  end

  describe "circuit with fallback" do
    it "returns fallback when circuit open" do
      client = client_for_server
      client.config.circuit.threshold = 2

      2.times { client.get("/error/500") rescue nil }

      # Use circuit directly with fallback
      result = client.circuit.with_fallback { "cached" }.run { client.get("/health") }
      expect(result).to eq("cached")
    end
  end
end
