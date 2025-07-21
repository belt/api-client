require_relative "base"

module Support
  class TestServer
    module Routes
      # ReportGenerator: /reports/:type/sections → section_ids,
      #   /reports/:type/sections/:id → section content
      class Reports
        include Base

        def self.prefix = %r{^/reports}

        def call(request)
          case request.path_info
          when %r{^/reports/([^/]+)/sections$}
            json(200, section_ids: %w[overview details appendix])
          when %r{^/reports/([^/]+)/sections/([^/]+)$}
            json(200, content: "Section data here")
          end
        end
      end
    end
  end
end
