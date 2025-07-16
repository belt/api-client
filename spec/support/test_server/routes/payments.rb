require_relative "base"

module Support
  class TestServer
    module Routes
      # PayReconciler: /payments/batches/:id/gateways → gateway_ids,
      #   /gateways/:id/settlements → transaction records
      class Payments
        include Base

        def self.prefix = %r{^/(payments|gateways)}

        def call(request)
          case request.path_info
          when %r{^/payments/batches/([^/]+)/gateways$}
            json(200, gateway_ids: %w[stripe braintree])
          when %r{^/gateways/([^/]+)/settlements$}
            json(200, transactions: [{id: "TXN-1", amount: 100}])
          end
        end
      end
    end
  end
end
