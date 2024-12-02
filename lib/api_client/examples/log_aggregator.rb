require "api_client/base"

module ApiClient
  module Examples
    # Sequential + Async: Log aggregation pipeline
    #
    # Sequential adapter fetches log shards in order (time-series),
    # Async processor (fork-based) parses and indexes entries.
    #
    # Use case: Observability — fetch log shard index → sequential
    # fan-out (chronological order) → async-process log parsing.
    #
    # @example
    #   client = LogAggregator.new
    #   results = client.aggregate(service: "api-gateway", window: "1h")
    #
    class LogAggregator < Base
      ADAPTER = :sequential
      PROCESSOR = :async

      def initialize(**options)
        super(base_path: "/logs", **options)
      end

      # @param service [String] Service name
      # @param window [String] Time window
      # @return [Array<Hash>] Parsed log entries
      def aggregate(service:, window:)
        request_flow
          .fetch(:get, "/services/#{service}/shards", params: {window: window})
          .then { |resp| JSON.parse(resp.body)["shard_ids"] }
          .fan_out(
            on_ready: :batch,
            on_fail: :skip,
            order: :preserve,
            timeout_ms: 15_000,
            retries: {max: 1, backoff: :linear}
          ) { |id| {method: :get, path: "/shards/#{id}/entries"} }
          .async_map(recipe: Transforms::Recipe.default, errors: Processing::ErrorStrategy.skip)
          .collect
      end
    end
  end
end
