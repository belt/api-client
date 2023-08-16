module Support
  # In-process mock HTTP endpoint for unit tests
  #
  # Uses Async::HTTP::Mock::Endpoint to intercept requests without
  # real TCP connections. Fast, deterministic, no threads.
  #
  # Use this for:
  # - Unit tests that need HTTP client behavior without network
  # - Testing request/response transformation logic
  # - Fast feedback loops during development
  #
  # Use TestServer instead for:
  # - Integration tests needing real TCP (timeouts, connection failures)
  # - Testing actual HTTP behavior over the wire
  # - Circuit breaker tests with real failures
  #
  # @example Basic usage
  #   it "makes requests" do
  #     with_mock_http do |mock|
  #       mock.respond { |req| [200, {}, ["OK"]] }
  #       # ... test code using Async::HTTP::Client
  #     end
  #   end
  #
  # @example With RSpec metadata
  #   RSpec.describe MyClient, :mock_http do
  #     before do
  #       mock_server.respond { |req| [200, {}, ["OK"]] }
  #     end
  #
  #     it "works" do
  #       # mock_server is available via let
  #     end
  #   end
  #
  module MockHttpHelper
    # Run block with a mock HTTP endpoint
    def with_mock_http(&block)
      require "async/http"
      require "async/http/mock"

      Sync do
        mock = MockServer.new
        mock.start
        yield mock
      ensure
        mock&.stop
      end
    end

    class MockServer
      attr_reader :endpoint

      def initialize
        @endpoint = Async::HTTP::Mock::Endpoint.new
        @handler = ->(request) { Protocol::HTTP::Response[200, {}, ["OK"]] }
      end

      # Set response handler
      # @yield [Protocol::HTTP::Request] The incoming request
      # @return [Protocol::HTTP::Response] or [status, headers, body] array
      def respond(&response_block)
        @handler = lambda { |request|
          result = response_block.call(request)
          if result.is_a?(Array)
            Protocol::HTTP::Response[result[0], result[1] || {}, result[2] || []]
          else
            result
          end
        }
      end

      # Wrap a target endpoint to route through mock
      def wrap(target_endpoint)
        @endpoint.wrap(target_endpoint)
      end

      def start
        @task = Async(transient: true) do
          @endpoint.run { |request| @handler.call(request) }
        end
      end

      def stop
        @task&.stop
      end
    end
  end
end

RSpec.configure do |config|
  config.include Support::MockHttpHelper, :mock_http
end
