begin
  require "async"
  require "async/http/internet"
rescue LoadError
  # async/async-http is optional; AsyncAdapter unavailable without it
end

require "json"
require "uri"
require_relative "base"
require_relative "instrumentation"

module ApiClient
  module Adapters
    # Async adapter for concurrent HTTP requests
    #
    # Uses Ruby 3+ fibers via async gem for concurrent execution.
    # Normalizes Async::HTTP responses to Faraday::Response.
    #
    # A new Async::HTTP::Internet instance is created per #execute call
    # for isolation — each batch gets its own connection pool and cleanup.
    # This trades connection reuse across batches for simpler lifecycle
    # management. For high-frequency batches to the same host, consider
    # Typhoeus which reuses connections via libcurl's connection cache.
    #
    class AsyncAdapter
      include Base
      include Instrumentation

      attr_reader :config

      # @param config [Configuration] ApiClient configuration
      def initialize(config = ApiClient.configuration)
        @config = config
      end

      # Execute requests concurrently using fibers
      # @param requests [Array<Hash>] Array of request hashes
      # @return [Array<Faraday::Response>]
      def execute(requests)
        return [] if requests.empty?

        with_batch_instrumentation(:async, requests) do
          run_async(requests)
        end
      end

      private

      def run_async(requests)
        Sync do |task|
          internet = ::Async::HTTP::Internet.new

          tasks = requests.map do |request|
            task.async do
              execute_request(internet, request)
            end
          end

          tasks.map(&:wait)
        ensure
          internet&.close
        end
      end

      def execute_request(internet, request)
        uri = build_uri(request[:path])
        method = request[:method].to_s.upcase
        headers = build_headers(request[:headers])
        body = encode_body(request[:body])

        response = internet.call(method, uri, headers, body)
        normalize_response(response, uri)
      rescue Async::TimeoutError, Errno::ECONNREFUSED, SocketError, IOError => error
        build_error_response(error, uri)
      end

      def build_uri(path)
        base = @base_uri ||= URI.join(config.service_uri, config.base_path).freeze
        uri = URI.join(base, path).to_s
        validate_uri!(uri)
        uri
      end

      def build_headers(headers)
        merged = config.default_headers.merge(headers || {})
        merged.map { |key, value| [key, value] }
      end

      # Normalize Async::HTTP response to Faraday::Response
      def normalize_response(response, uri)
        build_faraday_response(
          status: response.status,
          headers: response.headers.to_h,
          body: response.read,
          url: uri
        )
      end
    end
  end
end
