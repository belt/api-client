require "api_client/base"

module ApiClient
  module Examples
    # Sequential + Ractor: Batch user profile enrichment
    #
    # Sequential adapter fetches user profiles one at a time
    # (strict ordering required), Ractor pool processes heavy
    # profile normalization in parallel.
    #
    # Use case: CRM enrichment — fetch user list → sequential
    # fan-out (API requires ordered access) → Ractor-parallel
    # profile normalization.
    #
    # @example
    #   client = UserEnricher.new
    #   results = client.enrich(segment_id: "SEG-500")
    #
    class UserEnricher < Base
      ADAPTER = :sequential
      PROCESSOR = :ractor

      def initialize(**options)
        super(base_path: "/users", **options)
      end

      # @param segment_id [String]
      # @return [Array<Hash>] Enriched user profiles
      def enrich(segment_id:)
        request_flow
          .fetch(:get, "/segments/#{segment_id}/members")
          .then { |resp| JSON.parse(resp.body)["user_ids"] }
          .fan_out(
            on_ready: :batch,
            on_fail: :collect,
            order: :preserve,
            timeout_ms: 10_000,
            retries: {max: 2, backoff: :exponential}
          ) { |id| {method: :get, path: "/profiles/#{id}"} }
          .parallel_map(recipe: Transforms::Recipe.default, errors: Processing::ErrorStrategy.collect)
          .collect
      end
    end
  end
end
