require "api_client/base"

module ApiClient
  module Examples
    # Typhoeus + Ractor: High-throughput order fulfillment
    #
    # Typhoeus (HTTP/2 pipelining) fetches order manifests concurrently,
    # Ractor processes heavy JSON payloads in true parallel isolation.
    #
    # Use case: E-commerce order pipeline — fetch order → extract line items
    # → fan-out to inventory service → parse responses with Ractor pool.
    #
    # @example
    #   client = OrderFulfiller.new
    #   results = client.fulfill_orders(order_id: "ORD-9001")
    #
    class OrderFulfiller < Base
      ADAPTER = :typhoeus
      PROCESSOR = :ractor

      def initialize(**options)
        super(base_path: "/orders", **options)
      end

      # @param order_id [String]
      # @return [Array<Hash>] Parsed inventory check results
      def fulfill_orders(order_id:)
        request_flow
          .fetch(:get, "/#{order_id}")
          .then { |resp| JSON.parse(resp.body)["line_item_ids"] }
          .fan_out(
            on_ready: :batch,
            on_fail: :collect,
            timeout_ms: 5000,
            retries: {max: 2, backoff: :exponential}
          ) { |id| {method: :get, path: "/inventory/#{id}"} }
          .parallel_map(recipe: Transforms::Recipe.default, errors: Processing::ErrorStrategy.collect)
          .collect
      end
    end
  end
end
