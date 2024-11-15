require "api_client/base"

module ApiClient
  module Examples
    # Async + Concurrent: Multi-channel notification dispatch
    #
    # Async fibers fan out delivery requests to channel gateways,
    # Concurrent-ruby thread pool processes delivery receipts.
    #
    # Use case: Notification service — fetch recipients → fan-out
    # to SMS/email/push gateways → thread-pool parse receipts.
    #
    # @example
    #   client = NotifyDispatcher.new
    #   results = client.dispatch(campaign_id: "CAMP-77")
    #
    class NotifyDispatcher < Base
      ADAPTER = :async
      PROCESSOR = :concurrent

      def initialize(**options)
        super(base_path: "/notifications", **options)
      end

      # @param campaign_id [String]
      # @return [Array<Hash>] Delivery receipts
      def dispatch(campaign_id:)
        request_flow
          .fetch(:get, "/campaigns/#{campaign_id}/recipients")
          .then { |resp| JSON.parse(resp.body)["recipient_ids"] }
          .fan_out(
            on_ready: :batch,
            on_fail: :skip,
            timeout_ms: 8000,
            retries: {max: 2, backoff: :exponential}
          ) { |id| {method: :post, path: "/deliver/#{id}"} }
          .concurrent_map(
            recipe: Transforms::Recipe.default,
            errors: Processing::ErrorStrategy.skip
          )
          .collect
      end
    end
  end
end
