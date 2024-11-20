require "api_client/base"

module ApiClient
  module Examples
    # Concurrent + Ractor: Threat intelligence scanning
    #
    # Concurrent backend fans out to threat-intel endpoints with
    # thread-based parallel HTTP, Ractor processor computes content
    # hashes in parallel for IOC matching (CPU-bound).
    #
    # Use case: Security platform — fetch indicator list → concurrent
    # fan-out to threat feeds → Ractor-parallel hash verification.
    #
    # @example
    #   client = ThreatScanner.new
    #   results = client.scan(indicator_id: "IOC-8842")
    #
    class ThreatScanner < Base
      ADAPTER = :concurrent
      PROCESSOR = :ractor

      def initialize(**options)
        super(base_path: "/threats", **options)
      end

      # @param indicator_id [String]
      # @return [Array<Hash>] Matched threat indicators with hashes
      def scan(indicator_id:)
        request_flow
          .fetch(:get, "/indicators/#{indicator_id}/feeds")
          .then { |resp| JSON.parse(resp.body)["feed_ids"] }
          .fan_out(
            on_ready: :batch,
            on_fail: :skip,
            timeout_ms: 8000,
            retries: {max: 2, backoff: :exponential}
          ) { |id| {method: :get, path: "/feeds/#{id}/check"} }
          .parallel_map(
            recipe: Transforms::Recipe.new(extract: :body, transform: :sha256),
            errors: Processing::ErrorStrategy.skip
          )
          .collect
      end
    end
  end
end
