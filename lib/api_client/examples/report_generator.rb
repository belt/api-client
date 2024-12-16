require "api_client/base"

module ApiClient
  module Examples
    # Sequential + Sequential: Simple report generation
    #
    # Sequential adapter fetches pages one at a time (rate-limited API),
    # Sequential processor parses responses in order.
    #
    # Use case: Rate-limited reporting API — fetch report index
    # → sequential fan-out (respects rate limits) → sequential parse.
    #
    # @example
    #   client = ReportGenerator.new
    #   results = client.generate(report_type: "monthly-summary")
    #
    class ReportGenerator < Base
      ADAPTER = :sequential
      PROCESSOR = :sequential

      def initialize(**options)
        super(base_path: "/reports", **options)
      end

      # @param report_type [String]
      # @return [Array<Hash>] Report sections
      def generate(report_type:)
        request_flow
          .fetch(:get, "/#{report_type}/sections")
          .then { |resp| JSON.parse(resp.body)["section_ids"] }
          .fan_out(
            on_ready: :batch,
            on_fail: :replace,
            order: :preserve,
            timeout_ms: 20_000,
            retries: {max: 1, backoff: :linear}
          ) { |id| {method: :get, path: "/#{report_type}/sections/#{id}"} }
          .process(
            recipe: Transforms::Recipe.default,
            errors: Processing::ErrorStrategy.replace({"content" => ""})
          )
          .collect
      end
    end
  end
end
