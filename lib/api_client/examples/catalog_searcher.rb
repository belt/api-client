require "api_client/base"

module ApiClient
  module Examples
    # Typhoeus + Async: Catalog search across multiple providers
    #
    # Typhoeus fans out search queries to provider APIs,
    # Async (fork-based) merges and deduplicates result sets.
    #
    # Use case: Product catalog — search query → fan-out to providers
    # → async-process merged results.
    #
    # @example
    #   client = CatalogSearcher.new
    #   results = client.search(query: "ruby book")
    #
    class CatalogSearcher < Base
      ADAPTER = :typhoeus
      PROCESSOR = :async

      def initialize(**options)
        super(base_path: "/catalog", **options)
      end

      # @param query [String] Search term
      # @return [Array<Hash>] Deduplicated search results
      def search(query:)
        request_flow
          .fetch(:get, "/providers")
          .then { |resp| JSON.parse(resp.body)["provider_ids"] }
          .fan_out(
            on_ready: :stream,
            on_fail: :skip,
            timeout_ms: 3000,
            retries: {max: 1, backoff: :linear}
          ) { |id| {method: :get, path: "/providers/#{id}/search", params: {q: query}} }
          .async_map(recipe: Transforms::Recipe.default, errors: Processing::ErrorStrategy.skip)
          .collect
      end
    end
  end
end
