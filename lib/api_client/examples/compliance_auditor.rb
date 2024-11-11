require "api_client/base"

module ApiClient
  module Examples
    # Typhoeus + Concurrent: Compliance report generation
    #
    # Typhoeus fetches audit logs from multiple services,
    # Concurrent-ruby thread pool processes and checksums entries.
    #
    # Use case: SOC2 compliance — fetch audit endpoints → fan-out
    # → thread-pool hash verification of each entry.
    #
    # @example
    #   client = ComplianceAuditor.new
    #   results = client.build_report(tenant_id: "T-100")
    #
    class ComplianceAuditor < Base
      ADAPTER = :typhoeus
      PROCESSOR = :concurrent

      def initialize(**options)
        super(base_path: "/compliance", **options)
      end

      # @param tenant_id [String]
      # @return [Array<Hash>] Audit entries with integrity checksums
      def build_report(tenant_id:)
        request_flow
          .fetch(:get, "/tenants/#{tenant_id}/audit-sources")
          .then { |resp| JSON.parse(resp.body)["source_ids"] }
          .fan_out(
            on_ready: :batch,
            on_fail: :fail_fast,
            timeout_ms: 10_000,
            retries: {max: 3, backoff: :exponential}
          ) { |id| {method: :get, path: "/audit/#{id}/entries"} }
          .concurrent_map(
            recipe: Transforms::Recipe.default,
            errors: Processing::ErrorStrategy.fail_fast
          )
          .collect
      end
    end
  end
end
