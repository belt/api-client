module ApiClient
  # Shared Faraday::Response construction for error and success cases.
  #
  # Used by Connection (sequential requests) and Adapters::Base (batch
  # requests) to eliminate duplicated response-wrapping logic.
  #
  # @example Build an error response
  #   ResponseBuilder.error_response(error, uri: "https://api.example.com/path")
  #
  # @example Build a success response
  #   ResponseBuilder.faraday_response(status: 200, headers: {}, body: "ok", url: uri)
  #
  module ResponseBuilder
    # Frozen header key to avoid per-call allocation
    ERROR_CLASS_HEADER = "X-Error-Class".freeze

    class << self
      # Wrap an error in a synthetic Faraday::Response so callers can
      # safely chain .status / .body regardless of error handling strategy.
      #
      # @param error [Exception] The error that occurred
      # @param uri [String, URI] Request URI (default: about:blank)
      # @return [Faraday::Response]
      def error_response(error, uri: URI("about:blank"))
        faraday_response(
          status: 0,
          headers: {ERROR_CLASS_HEADER => error.class.name},
          body: error.message,
          url: uri
        )
      end

      # Build a Faraday::Response from raw components
      #
      # @param status [Integer] HTTP status code
      # @param headers [Hash] Response headers
      # @param body [String] Response body
      # @param url [String, URI] Request URL
      # @return [Faraday::Response]
      def faraday_response(status:, headers:, body:, url:)
        env = Faraday::Env.new.tap do |e|
          e.status = status
          e.response_headers = headers
          e.body = body
          e.url = url.is_a?(URI) ? url : URI.parse(url.to_s)
        end

        Faraday::Response.new(env)
      end
    end
  end
end
