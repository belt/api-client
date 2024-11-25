require "api_client/base"

module ApiClient
  module Examples
    # Concurrent + Concurrent: Payment reconciliation
    #
    # Concurrent-ruby thread pool fans out to payment gateway APIs,
    # Concurrent-ruby thread pool processes transaction matching.
    #
    # Use case: FinTech reconciliation — fetch settlement batches
    # → thread-pool fan-out to gateways → thread-pool match transactions.
    #
    # @example
    #   client = PayReconciler.new
    #   results = client.reconcile(batch_id: "BATCH-2024-01")
    #
    class PayReconciler < Base
      ADAPTER = :concurrent
      PROCESSOR = :concurrent

      def initialize(**options)
        super(base_path: "/payments", **options)
      end

      # @param batch_id [String]
      # @return [Array<Hash>] Reconciled transaction records
      def reconcile(batch_id:)
        request_flow
          .fetch(:get, "/batches/#{batch_id}/gateways")
          .then { |resp| JSON.parse(resp.body)["gateway_ids"] }
          .fan_out(
            on_ready: :batch,
            on_fail: :collect,
            timeout_ms: 10_000,
            retries: {max: 3, backoff: :exponential}
          ) { |id| {method: :get, path: "/gateways/#{id}/settlements"} }
          .concurrent_map(
            recipe: Transforms::Recipe.default,
            errors: Processing::ErrorStrategy.collect
          )
          .collect
      end
    end
  end
end
