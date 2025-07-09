require_relative "base"

module Support
  class TestServer
    module Routes
      # LegacyExporter: /legacy/v1/:resource/pages → page_ids,
      #   /legacy/v1/:resource/pages/:id → records
      class Legacy
        include Base

        def self.prefix = %r{^/legacy}

        def call(request)
          case request.path_info
          when %r{^/legacy/v1/([^/]+)/pages$}
            json(200, page_ids: %w[PG-1 PG-2])
          when %r{^/legacy/v1/([^/]+)/pages/([^/]+)$}
            json(200, records: [{id: 1, name: "Acme Corp"}])
          end
        end
      end
    end
  end
end
