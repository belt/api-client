# frozen_string_literal: true

require "spec_helper"
require_relative "../support/chaos/toxiproxy_harness"

# standard:disable RSpec/DescribeClass -- these examples document deliberate transport-level faults
RSpec.describe "ApiClient transport faults through Toxiproxy", :chaos do
  let(:harness) { Support::Chaos::ToxiproxyHarness.new }
  let(:proxy) { harness.proxy }

  before { harness.start }
  after { harness.stop }

  it "passes a response through with added latency below the client timeout" do
    proxy.toxic(:latency, latency: 50).apply do
      response = chaos_client(read_timeout: 2).get("/health")

      expect(response.status).to eq(200)
    end
    # standard:enable RSpec/DescribeClass
  end

  it "rejects requests while the proxy is disabled" do
    proxy.down do
      expect { chaos_client(retry: {max: 0}).get("/health") }
        .to raise_error(Faraday::ConnectionFailed)
    end
  end

  it "recovers after the proxy is re-enabled" do
    proxy.down {}

    expect(chaos_client.get("/health").status).to eq(200)
  end

  it "exposes a connection reset injected by Toxiproxy" do
    proxy.toxic(:reset_peer).apply do
      expect { chaos_client(retry: {max: 0}).get("/health") }
        .to raise_error(Faraday::Error)
    end
  end

  it "opens the circuit after repeated failures from a disabled proxy" do
    client = chaos_client(retry: {max: 0}, circuit: {threshold: 2, cool_off: 60})
    proxy.down { 2.times { request_and_ignore_connection_failure(client) } }

    expect { client.get("/health") }.to raise_error(ApiClient::CircuitOpenError)
  end

  def chaos_client(**options)
    ApiClient::TestClient.new(
      service_uri: harness.base_url,
      test_id: SecureRandom.hex(4),
      **options
    )
  end

  def request_and_ignore_connection_failure(client)
    client.get("/health")
  rescue Faraday::ConnectionFailed
    nil
  end
end
