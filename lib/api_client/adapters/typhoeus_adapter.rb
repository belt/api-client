require "json"

begin
  require "typhoeus"
rescue LoadError
  # typhoeus is optional; TyphoeusAdapter unavailable without it
end

require_relative "base"
require_relative "instrumentation"

module ApiClient
  module Adapters
    # Typhoeus adapter for concurrent HTTP requests
    #
    # Uses Hydra for concurrent request execution with HTTP/2 support.
    # Normalizes Typhoeus::Response to Faraday::Response for transparency.
    #
    class TyphoeusAdapter
      include Base
      include Instrumentation

      attr_reader :config

      # @param config [Configuration] ApiClient configuration
      def initialize(config = ApiClient.configuration)
        @config = config
        @base_uri = URI.join(config.service_uri, config.base_path).freeze
      end

      # Execute requests concurrently
      # @param requests [Array<Hash>] Array of request hashes
      # @return [Array<Faraday::Response>]
      def execute(requests)
        return [] if requests.empty?

        with_batch_instrumentation(:typhoeus, requests) do
          execute_with_hydra(requests)
        end
      end

      private

      def execute_with_hydra(requests)
        results = Array.new(requests.size)
        hydra = ::Typhoeus::Hydra.new

        requests.each_with_index do |request, index|
          typhoeus_request = build_request(request)

          typhoeus_request.on_complete do |response|
            results[index] = normalize_response(response)
          end

          hydra.queue(typhoeus_request)
        end

        hydra.run
        results
      end

      def build_request(request)
        uri = build_uri(request[:path])

        ::Typhoeus::Request.new(
          uri,
          method: request[:method],
          body: encode_body(request[:body]),
          headers: merged_headers(request[:headers]),
          params: request[:params],
          timeout: config.read_timeout,
          connecttimeout: config.open_timeout,
          # HTTP/2 and TCP options set per-request via libcurl
          http_version: :httpv2_tls,
          tcp_nodelay: true,
          tcp_keepalive: true
        )
      end

      def build_uri(path)
        uri = URI.join(@base_uri, path).to_s
        validate_uri!(uri)
        uri
      end

      # Normalize Typhoeus::Response to Faraday::Response
      # @param typhoeus_response [Typhoeus::Response]
      # @return [Faraday::Response]
      def normalize_response(typhoeus_response)
        return timeout_error_response(typhoeus_response) if typhoeus_response.timed_out?
        return connection_error_response(typhoeus_response) if typhoeus_response.code.zero?

        build_faraday_response(
          status: typhoeus_response.code,
          headers: parse_headers(typhoeus_response.headers),
          body: typhoeus_response.body,
          url: typhoeus_response.effective_url || ""
        )
      end

      def parse_headers(headers)
        return {} if headers.nil?

        # Typhoeus returns headers as Hash or String
        case headers
        when Hash then headers
        when String then parse_header_string(headers)
        else {}
        end
      end

      def parse_header_string(header_string)
        header_string.split("\r\n").each_with_object({}) do |line, hash|
          key, value = line.split(": ", 2)
          hash[key] = value if key && value
        end
      end

      def timeout_error_response(typhoeus_response)
        build_error_response(
          Faraday::TimeoutError.new("Request timed out"),
          typhoeus_response.effective_url || ""
        )
      end

      def connection_error_response(typhoeus_response)
        build_error_response(
          Faraday::ConnectionFailed.new(typhoeus_response.return_message),
          typhoeus_response.effective_url || ""
        )
      end
    end
  end
end
