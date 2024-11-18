require "api_client/base"

module ApiClient
  module Examples
    # Async + Sequential: Configuration snapshot collection
    #
    # Async fibers fan out to config endpoints across environments,
    # Sequential processor handles ordered config merging.
    #
    # Use case: Config management — fetch environment list → fan-out
    # config fetches → sequential merge (order matters for overrides).
    #
    # @example
    #   client = ConfigSnapshot.new
    #   results = client.snapshot(app: "billing-service")
    #
    class ConfigSnapshot < Base
      ADAPTER = :async
      PROCESSOR = :sequential

      def initialize(**options)
        super(base_path: "/config", **options)
      end

      # @param app [String] Application name
      # @return [Array<Hash>] Config snapshots per environment
      def snapshot(app:)
        request_flow
          .fetch(:get, "/apps/#{app}/environments")
          .then { |resp| JSON.parse(resp.body)["environment_ids"] }
          .fan_out(
            on_ready: :batch,
            on_fail: :replace,
            order: :preserve,
            timeout_ms: 5000,
            retries: {max: 1, backoff: :linear}
          ) { |id| {method: :get, path: "/apps/#{app}/environments/#{id}/snapshot"} }
          .process(recipe: Transforms::Recipe.default, errors: Processing::ErrorStrategy.replace({}))
          .collect
      end
    end
  end
end
