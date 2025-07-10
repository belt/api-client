require_relative "base"

module Support
  class TestServer
    module Routes
      # NotifyDispatcher: /notifications/campaigns/:id/recipients → recipient_ids,
      #   /deliver/:id → delivery receipt
      class Notifications
        include Base

        def self.prefix = %r{^/(notifications|deliver)}

        def call(request)
          case request.path_info
          when %r{^/notifications/campaigns/([^/]+)/recipients$}
            json(200, recipient_ids: %w[R-1 R-2])
          when %r{^/deliver/([^/]+)$}
            json(200, delivered: true, channel: "email")
          end
        end
      end
    end
  end
end
