require "api_client/base"

module ApiClient
  module Examples
    # Typhoeus + Sequential: Legacy system data export
    #
    # Typhoeus fans out page fetches to a legacy API,
    # Sequential processor handles fragile XML-to-JSON transforms
    # one at a time to avoid overwhelming the parser.
    #
    # Use case: Data migration — fetch paginated legacy endpoints
    # → sequential parse (no parallelism needed for small payloads).
    #
    # @example
    #   client = LegacyExporter.new
    #   results = client.export(resource: "customers")
    #
    class LegacyExporter < Base
      ADAPTER = :typhoeus
      PROCESSOR = :sequential

      def initialize(**options)
        super(base_path: "/legacy/v1", **options)
      end

      # @param resource [String] Legacy resource name
      # @return [Array<Hash>] Parsed records
      def export(resource:)
        request_flow
          .fetch(:get, "/#{resource}/pages")
          .then { |resp| JSON.parse(resp.body)["page_ids"] }
          .fan_out(
            on_ready: :batch,
            on_fail: :collect,
            timeout_ms: 15_000,
            retries: {max: 2, backoff: :linear}
          ) { |id| {method: :get, path: "/#{resource}/pages/#{id}"} }
          .process(recipe: Transforms::Recipe.default, errors: Processing::ErrorStrategy.replace({}))
          .collect
      end
    end
  end
end
