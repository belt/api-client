require_relative "base"

module Support
  class TestServer
    module Routes
      # ComplianceAuditor: /compliance/tenants/:id/audit-sources → source_ids,
      #   /audit/:id/entries → audit entries
      class Compliance
        include Base

        def self.prefix = %r{^/(compliance|audit)}

        def call(request)
          case request.path_info
          when %r{^/compliance/tenants/([^/]+)/audit-sources$}
            json(200, source_ids: %w[S-1 S-2 S-3])
          when %r{^/audit/([^/]+)/entries$}
            json(200, entries: [{action: "login", ts: 1_700_000_000}])
          end
        end
      end
    end
  end
end
