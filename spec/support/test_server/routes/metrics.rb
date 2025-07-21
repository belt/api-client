require_relative "base"

module Support
  class TestServer
    module Routes
      # MetricsCollector: /metrics/namespaces/:ns/sources → source_ids,
      #   /sources/:id/latest → metric data
      class Metrics
        include Base

        def self.prefix = %r{^/(metrics|sources)}

        def call(request)
          case request.path_info
          when %r{^/metrics/namespaces/([^/]+)/sources$}
            json(200, source_ids: %w[cpu memory disk])
          when %r{^/sources/([^/]+)/latest$}
            json(200, value: 42.5, unit: "percent")
          end
        end
      end
    end
  end
end
