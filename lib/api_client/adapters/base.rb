require "json"
require_relative "../response_builder"

module ApiClient
  module Adapters
    # Shared functionality for concurrent HTTP adapters
    #
    # Provides common methods for body encoding, error response building,
    # and URI validation (SSRF protection).
    # Include this module in adapter implementations to reduce duplication.
    #
    module Base
      # Encode request body to JSON if needed
      # @param body [Object, nil] Request body
      # @return [String, nil] Encoded body
      def encode_body(body)
        return nil if body.nil?
        return body if body.is_a?(String)

        JSON.generate(body)
      end

      # Validate a URI against SSRF policy before request dispatch
      # @param uri [String, URI] URI to validate
      # @raise [SsrfBlockedError] if URI violates policy
      # @return [void]
      def validate_uri!(uri)
        UriPolicy.validate!(uri, config)
      rescue SsrfBlockedError => error
        Hooks.instrument(:request_blocked, url: uri.to_s, reason: error.reason)
        raise
      end

      # Build a Faraday::Response for error cases
      # @param error [Exception] The error that occurred
      # @param uri [String, URI] Request URI
      # @return [Faraday::Response]
      def build_error_response(error, uri)
        Hooks.instrument(:request_error, url: uri.to_s, error: error)
        ResponseBuilder.error_response(error, uri: uri)
      end

      # Merge headers with defaults from config
      # @param headers [Hash, nil] Request-specific headers
      # @return [Hash] Merged headers
      def merged_headers(headers)
        config.default_headers.merge(headers || {})
      end

      # Build a Faraday::Response from raw components
      # @param status [Integer] HTTP status code
      # @param headers [Hash] Response headers
      # @param body [String] Response body
      # @param url [String, URI] Request URL
      # @return [Faraday::Response]
      def build_faraday_response(status:, headers:, body:, url:)
        ResponseBuilder.faraday_response(status: status, headers: headers, body: body, url: url)
      end
    end
  end
end
