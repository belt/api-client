require "api_client/base"

module ApiClient
  module Examples
    # Async + Async: Distributed service health checks
    #
    # Async fibers fan out health pings to microservices,
    # Async processor (fork-based) aggregates and scores results.
    #
    # Use case: Platform health dashboard — discover services
    # → fiber fan-out health checks → async-process status aggregation.
    #
    # @example
    #   client = HealthChecker.new
    #   results = client.check(cluster: "us-east-1")
    #
    class HealthChecker < Base
      ADAPTER = :async
      PROCESSOR = :async

      def initialize(**options)
        super(base_path: "/health", **options)
      end

      # @param cluster [String] Cluster identifier
      # @return [Array<Hash>] Service health statuses
      def check(cluster:)
        request_flow
          .fetch(:get, "/clusters/#{cluster}/services")
          .then { |resp| JSON.parse(resp.body)["service_ids"] }
          .fan_out(
            on_ready: :stream,
            on_fail: :collect,
            timeout_ms: 2000,
            retries: false
          ) { |id| {method: :get, path: "/services/#{id}/ping"} }
          .async_map(
            recipe: Transforms::Recipe.default,
            errors: Processing::ErrorStrategy.replace({"status" => "unknown"})
          )
          .collect
      end
    end
  end
end
