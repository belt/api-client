require "json"
require "puma"
require "puma/configuration"
require "puma/launcher"
require "rack"
require_relative "router"

module Support
  # Real TCP test server for integration specs
  #
  # Runs Puma in a background thread to provide actual HTTP endpoints.
  # Uses Puma instead of Falcon to avoid a jemalloc + Ruby 3.4 segfault
  # on macOS x86_64 triggered by Async::Container::Threaded's concurrent
  # kqueue initialisation.
  #
  # Routes are defined in spec/support/test_server/routes/ — one file per domain.
  # The Router dispatches to the first matching route module.
  #
  # Use this for:
  # - Integration tests with real TCP connections
  # - Testing timeouts and connection failures
  # - Circuit breaker tests with real failures
  # - End-to-end HTTP behavior verification
  # - Example API client integration tests
  #
  # Use MockHttpHelper instead for:
  # - Unit tests that just need request/response flow
  # - Fast, deterministic tests without network
  # - Tests that don't need real TCP behavior
  #
  # @example Via shared context
  #   RSpec.describe MyClient, :integration do
  #     it "works" do
  #       client = client_for_server
  #       response = client.get("/health")
  #       expect(response.status).to eq(200)
  #     end
  #   end
  #
  class TestServer
    attr_reader :port, :worker_count

    def initialize(port: 0)
      @port = port
      @requests = []
      @mutex = Mutex.new
      @launcher = nil
      @router = Router.new
      @worker_count = 2
    end

    def requests
      @mutex.synchronize { @requests.dup }
    end

    def start
      @port = available_port if @port.zero?
      rack_app = build_rack_app

      conf = Puma::Configuration.new do |config|
        config.bind "tcp://127.0.0.1:#{@port}"
        config.threads 2, 4
        config.log_requests false
        config.quiet true
        config.app rack_app
      end

      @launcher = Puma::Launcher.new(conf)
      @server_thread = Thread.new { @launcher.run } # standard:disable ThreadSafety/NewThread -- test helper requires background thread for Puma

      wait_for_server
      self
    end

    def stop
      @launcher&.stop
      @server_thread&.join(2)
      @launcher = nil
      @server_thread = nil
    end

    def base_url = "http://127.0.0.1:#{port}"

    def clear_requests
      @mutex.synchronize { @requests.clear }
    end

    private

    def available_port
      server = TCPServer.new("127.0.0.1", 0)
      server.addr[1]
    ensure
      server&.close
    end

    def wait_for_server
      20.times do
        return if server_ready?
        sleep 0.05
      end
      raise "Test server failed to start on port #{port}"
    end

    def server_ready?
      TCPSocket.new("127.0.0.1", port).close
      true
    rescue Errno::ECONNREFUSED
      false
    end

    def build_rack_app
      requests_ref = @requests
      mutex_ref = @mutex
      router = @router

      ->(env) {
        rack_request = Rack::Request.new(env)
        req_data = {method: rack_request.request_method, path: rack_request.fullpath}
        mutex_ref.synchronize { requests_ref << req_data }
        router.call(rack_request)
      }
    end
  end
end
