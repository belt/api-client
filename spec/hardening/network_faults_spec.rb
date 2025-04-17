require "spec_helper"
require "api_client"

RSpec.describe "Network fault handling", :chaos, :integration do
  # These tests require Toxiproxy server running:
  #   toxiproxy-server
  # Or via Docker:
  #   docker run -p 8474:8474 ghcr.io/shopify/toxiproxy

  describe "latency injection" do
    it "succeeds when latency is within timeout" do
      test_proxy.toxic(:latency, latency: 100).apply do
        client = chaos_client(read_timeout: 5)
        response = client.get("/health")
        expect(response.status).to eq(200)
      end
    end

    it "times out when latency exceeds timeout" do
      # Use timeout toxic which hangs then closes connection
      test_proxy.toxic(:timeout, timeout: 100).apply do
        client = chaos_client(read_timeout: 2, retry: {max: 0})
        expect { client.get("/health") }.to raise_error(Faraday::Error)
      end
    end

    it "handles jittery latency" do
      test_proxy.toxic(:latency, latency: 200, jitter: 100).apply do
        client = chaos_client(read_timeout: 5)
        responses = 3.times.map { client.get("/health") }
        expect(responses).to all(have_attributes(status: 200))
      end
    end
  end

  describe "connection failures" do
    it "raises connection error when proxy is disabled" do
      test_proxy.disable do
        client = chaos_client(retry: {max: 0})
        expect { client.get("/health") }.to raise_error(Faraday::ConnectionFailed)
      end
    end

    it "recovers after proxy is re-enabled" do
      test_proxy.disable
      client = chaos_client(retry: {max: 0})

      expect { client.get("/health") }.to raise_error(Faraday::ConnectionFailed)

      test_proxy.enable
      response = client.get("/health")
      expect(response.status).to eq(200)
    end
  end

  describe "bandwidth limiting" do
    it "handles slow responses with sufficient timeout" do
      # 1 KB/s bandwidth limit
      test_proxy.toxic(:bandwidth, rate: 1).apply do
        client = chaos_client(read_timeout: 10)
        response = client.get("/health")
        expect(response.status).to eq(200)
      end
    end
  end

  describe "connection reset" do
    it "raises error on reset_peer" do
      test_proxy.toxic(:reset_peer).apply do
        client = chaos_client(retry: {max: 0})
        expect { client.get("/health") }.to raise_error(Faraday::ConnectionFailed)
      end
    end
  end

  describe "timeout toxic" do
    it "hangs then closes connection" do
      # Timeout toxic: connection hangs for N ms then closes
      test_proxy.toxic(:timeout, timeout: 500).apply do
        client = chaos_client(read_timeout: 2, retry: {max: 0})
        expect { client.get("/health") }.to raise_error(Faraday::Error)
      end
    end
  end

  describe "data limiting" do
    it "closes connection after N bytes" do
      test_proxy.toxic(:limit_data, bytes: 10).apply do
        client = chaos_client(retry: {max: 0})
        # Response will be truncated/connection closed
        expect { client.get("/health") }.to raise_error(Faraday::Error)
      end
    end
  end

  describe "retry behavior under faults" do
    it "retries and eventually fails after max retries" do
      # Use timeout toxic to force failures
      test_proxy.toxic(:timeout, timeout: 100).apply do
        client = chaos_client(
          read_timeout: 2,
          retry: {max: 1, interval: 0.1}
        )

        # Should retry once then fail
        expect {
          client.get("/health")
        }.to raise_error(Faraday::Error)
      end
    end
  end

  describe "circuit breaker under faults" do
    it "opens circuit after repeated failures" do
      test_proxy.disable do
        client = chaos_client(
          retry: {max: 0},
          circuit: {threshold: 3, cool_off: 60}
        )

        # Trigger failures to open circuit
        3.times do
          client.get("/health")
        rescue Faraday::ConnectionFailed
          # Expected
        end

        expect(client.circuit_open?).to be true
      end
    end

    it "circuit prevents requests when open" do
      test_proxy.disable do
        client = chaos_client(
          retry: {max: 0},
          circuit: {threshold: 2, cool_off: 60}
        )

        # Open the circuit
        2.times do
          client.get("/health")
        rescue Faraday::ConnectionFailed
          # Expected
        end

        # Now circuit should be open and fail fast
        expect { client.get("/health") }.to raise_error(ApiClient::CircuitOpenError)
      end
    end
  end
end
