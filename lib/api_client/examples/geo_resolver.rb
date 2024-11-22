require "api_client/base"

module ApiClient
  module Examples
    # Concurrent + Async: Geographic routing resolution
    #
    # Concurrent-ruby thread pool fans out to regional DNS/routing APIs,
    # Async processor (fork-based) normalizes latency measurements.
    #
    # Use case: CDN routing — fetch edge locations → thread-pool
    # fan-out latency probes → async-process latency normalization.
    #
    # @example
    #   client = GeoResolver.new
    #   results = client.resolve(domain: "cdn.example.com")
    #
    class GeoResolver < Base
      ADAPTER = :concurrent
      PROCESSOR = :async

      def initialize(**options)
        super(base_path: "/routing", **options)
      end

      # @param domain [String] Domain to resolve
      # @return [Array<Hash>] Latency-scored edge locations
      def resolve(domain:)
        request_flow
          .fetch(:get, "/domains/#{domain}/edges")
          .then { |resp| JSON.parse(resp.body)["edge_ids"] }
          .fan_out(
            on_ready: :batch,
            on_fail: :skip,
            timeout_ms: 3000,
            retries: {max: 1, backoff: :linear}
          ) { |id| {method: :get, path: "/edges/#{id}/probe"} }
          .async_map(recipe: Transforms::Recipe.default, errors: Processing::ErrorStrategy.skip)
          .collect
      end
    end
  end
end
