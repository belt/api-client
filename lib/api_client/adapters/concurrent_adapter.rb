begin
  require "concurrent"
rescue LoadError
  # concurrent-ruby is optional; ConcurrentAdapter unavailable without it
end

require "faraday"
require "json"
require_relative "base"
require_relative "instrumentation"
require_relative "../concerns/poolable"

module ApiClient
  module Adapters
    # Concurrent-ruby adapter for concurrent HTTP requests
    #
    # Uses thread pool via Concurrent::Future for concurrent execution.
    # Faraday connections are pooled via ConnectionPool for thread safety.
    # Falls back to this when Typhoeus/Async unavailable.
    #
    class ConcurrentAdapter
      include Base
      include Instrumentation
      include Concerns::Poolable

      attr_reader :config

      # Backward-compatible accessor — checks out a connection for introspection
      # @return [Faraday::Connection]
      def connection
        with_pooled_connection { |conn| conn }
      end

      # @param config [Configuration] ApiClient configuration
      def initialize(config = ApiClient.configuration)
        @config = config
        @pool = build_pool(config.pool_config) { build_connection }
      end

      # Execute requests concurrently using thread pool
      # @param requests [Array<Hash>] Array of request hashes
      # @return [Array<Faraday::Response>]
      def execute(requests)
        return [] if requests.empty?

        with_batch_instrumentation(:concurrent, requests) do
          futures = requests.map do |request|
            ::Concurrent::Future.execute { execute_request(request) }
          end
          futures.map do |future|
            result = future.value(config.read_timeout)
            if result.nil? && future.rejected?
              build_error_response(future.reason || Timeout::Error.new("Future timed out"), base_uri)
            else
              result
            end
          end
        end
      end

      private

      def execute_request(request)
        validate_uri!(URI.join(base_uri, request[:path]))
        with_pooled_connection do |connection|
          connection.run_request(
            request[:method],
            request[:path],
            encode_body(request[:body]),
            merged_headers(request[:headers])
          ) do |faraday_request|
            faraday_request.params.update(request[:params] || {})
          end
        end
      rescue Faraday::Error, Timeout::Error, Errno::ECONNREFUSED => error
        build_error_response(error, URI.join(base_uri, request[:path]))
      end

      def build_connection
        Faraday.new(url: base_uri.dup) do |faraday|
          faraday.request :url_encoded
          faraday.request :json
          faraday.options[:timeout] = config.read_timeout
          faraday.options[:open_timeout] = config.open_timeout
          faraday.headers.update(config.default_headers)
          faraday.adapter :net_http
        end
      end

      def base_uri
        @base_uri ||= URI.join(config.service_uri, config.base_path).freeze
      end
    end
  end
end
