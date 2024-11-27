require "api_client/base"

module ApiClient
  module Examples
    # Concurrent + Sequential: Dependency graph construction
    #
    # Concurrent-ruby thread pool fans out to package registry APIs,
    # Sequential processor builds the dependency tree in order.
    #
    # Use case: Package manager — fetch root deps → thread-pool
    # fan-out to registry → sequential tree assembly (order-sensitive).
    #
    # @example
    #   client = DepGraphBuilder.new
    #   results = client.build_graph(package: "api_client")
    #
    class DepGraphBuilder < Base
      ADAPTER = :concurrent
      PROCESSOR = :sequential

      def initialize(**options)
        super(base_path: "/registry", **options)
      end

      # @param package [String] Root package name
      # @return [Array<Hash>] Dependency metadata in resolution order
      def build_graph(package:)
        request_flow
          .fetch(:get, "/packages/#{package}/dependencies")
          .then { |resp| JSON.parse(resp.body)["dep_names"] }
          .fan_out(
            on_ready: :batch,
            on_fail: :replace,
            order: :preserve,
            timeout_ms: 5000,
            retries: {max: 1, backoff: :linear}
          ) { |name| {method: :get, path: "/packages/#{name}/metadata"} }
          .process(
            recipe: Transforms::Recipe.default,
            errors: Processing::ErrorStrategy.replace({"name" => "unknown", "version" => "0.0.0"})
          )
          .collect
      end
    end
  end
end
