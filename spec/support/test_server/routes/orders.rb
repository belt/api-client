require_relative "base"

module Support
  class TestServer
    module Routes
      # OrderFulfiller: /orders/:id → line_item_ids, /inventory/:id → stock check
      class Orders
        include Base

        def self.prefix = %r{^/(orders|inventory)}

        def call(request)
          case request.path_info
          when %r{^/orders/([^/]+)$}
            json(200, line_item_ids: %w[LI-1 LI-2 LI-3])
          when %r{^/inventory/([^/]+)$}
            json(200, sku: "SKU-100", qty: 5)
          end
        end
      end
    end
  end
end
