require_relative "base"

module Support
  class TestServer
    module Routes
      # GeoResolver: /routing/domains/:domain/edges → edge_ids,
      #   /edges/:id/probe → latency measurement
      class Routing
        include Base

        def self.prefix = %r{^/(routing|edges)}

        def call(request)
          case request.path_info
          when %r{^/routing/domains/([^/]+)/edges$}
            json(200, edge_ids: %w[edge-us edge-eu])
          when %r{^/edges/([^/]+)/probe$}
            json(200, latency_ms: 42, region: "us-east-1")
          end
        end
      end
    end
  end
end
