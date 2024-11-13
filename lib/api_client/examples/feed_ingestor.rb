require "api_client/base"

module ApiClient
  module Examples
    # Async + Ractor: Real-time feed ingestion
    #
    # Async fibers fan out to event stream endpoints,
    # Ractor pool processes payloads with true CPU parallelism.
    #
    # Use case: Social media aggregator — fetch feed sources
    # → fiber-based fan-out → Ractor-parallel JSON normalization.
    #
    # @example
    #   client = FeedIngestor.new
    #   results = client.ingest(feed_id: "FEED-42")
    #
    class FeedIngestor < Base
      ADAPTER = :async
      PROCESSOR = :ractor

      def initialize(**options)
        super(base_path: "/feeds", **options)
      end

      # @param feed_id [String]
      # @return [Array<Hash>] Normalized feed entries
      def ingest(feed_id:)
        request_flow
          .fetch(:get, "/#{feed_id}/sources")
          .then { |resp| JSON.parse(resp.body)["source_urls"] }
          .fan_out(
            on_ready: :stream,
            on_fail: :skip,
            timeout_ms: 4000,
            retries: {max: 1, backoff: :exponential}
          ) { |url| {method: :get, path: url} }
          .parallel_map(recipe: Transforms::Recipe.default, errors: Processing::ErrorStrategy.skip)
          .collect
      end
    end
  end
end
