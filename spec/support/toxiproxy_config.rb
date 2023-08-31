require "toxiproxy"

# Check if Toxiproxy server is running
TOXIPROXY_AVAILABLE = begin
  Toxiproxy.version
  true
rescue Errno::ECONNREFUSED, Toxiproxy::NotFound
  warn "WARNING: Toxiproxy server not running. Chaos tests will be skipped."
  warn "  Start with: toxiproxy-server (or brew install toxiproxy)"
  false
end

# Toxiproxy proxy configuration
# Routes traffic through proxy to inject faults
TOXIPROXY_LISTEN_PORT = 22220
TOXIPROXY_PROXY_NAME = "api_client_test"

module Support
  module ToxiproxyHelper
    # Get the proxied URL for chaos tests
    # @return [String] URL pointing to Toxiproxy proxy
    def proxied_url
      "http://127.0.0.1:#{TOXIPROXY_LISTEN_PORT}"
    end

    # Create a client configured to use the Toxiproxy proxy
    # @param overrides [Hash] Additional configuration overrides
    # @return [ApiClient::Base]
    def chaos_client(**overrides)
      ApiClient::Base.new(service_uri: proxied_url, **overrides)
    end

    # Access the test proxy
    # @return [Toxiproxy::Proxy]
    def test_proxy
      Toxiproxy[TOXIPROXY_PROXY_NAME.to_sym]
    end
  end
end

RSpec.configure do |config|
  config.include Support::ToxiproxyHelper, :chaos

  config.before(:each, :chaos) do
    skip "Toxiproxy server not running" unless TOXIPROXY_AVAILABLE

    # Dynamically configure proxy to point to the test server
    upstream_port = TestServerHolder.instance&.port
    skip "Test server not running" unless upstream_port

    begin
      Toxiproxy.populate([
        {
          name: TOXIPROXY_PROXY_NAME,
          listen: "127.0.0.1:#{TOXIPROXY_LISTEN_PORT}",
          upstream: "127.0.0.1:#{upstream_port}"
        }
      ])
    rescue Errno::ECONNREFUSED
      skip "Toxiproxy server not running"
    end
  end

  config.after(:each, :chaos) do
    next unless TOXIPROXY_AVAILABLE

    begin
      Toxiproxy.reset
    rescue Errno::ECONNREFUSED
      # Server went away during test
    end
  end
end
