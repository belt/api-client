require "api_client/base"

module ApiClient
  module Examples
    # Sequential + Concurrent: Metrics collection pipeline
    #
    # Sequential adapter fetches metric endpoints in order,
    # Concurrent-ruby thread pool processes metric aggregation.
    #
    # Use case: Monitoring — fetch metric sources → sequential
    # fan-out (deterministic ordering) → thread-pool aggregation.
    #
    # @example
    #   client = MetricsCollector.new
    #   results = client.collect_metrics(namespace: "production")
    #
    class MetricsCollector < Base
      ADAPTER = :sequential
      PROCESSOR = :concurrent

      def initialize(**options)
        super(base_path: "/metrics", **options)
      end

      # @param namespace [String] Metrics namespace
      # @return [Array<Hash>] Aggregated metric data
      def collect_metrics(namespace:)
        request_flow
          .fetch(:get, "/namespaces/#{namespace}/sources")
          .then { |resp| JSON.parse(resp.body)["source_ids"] }
          .fan_out(
            on_ready: :batch, on_fail: :replace,
            order: :preserve, timeout_ms: 5000,
            retries: {max: 2, backoff: :exponential}
          ) { |id| {method: :get, path: "/sources/#{id}/latest"} }
          .concurrent_map(
            recipe: Transforms::Recipe.default,
            errors: Processing::ErrorStrategy.replace({"value" => 0})
          )
          .collect
      end
    end
  end
end
