require_relative "base"

module Support
  class TestServer
    module Routes
      # HealthChecker: /health/clusters/:cluster/services → service_ids,
      #   /services/:id/ping → health status
      #
      # Note: /health (bare) is handled by Core. This handles the
      # /health/clusters sub-path and /services paths.
      class HealthClusters
        include Base

        def self.prefix = %r{^/(health/clusters|services)}

        def call(request)
          case request.path_info
          when %r{^/health/clusters/([^/]+)/services$}
            json(200, service_ids: %w[svc-a svc-b svc-c])
          when %r{^/services/([^/]+)/ping$}
            json(200, status: "healthy", latency_ms: 12)
          end
        end
      end
    end
  end
end
