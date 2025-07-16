require_relative "base"

module Support
  class TestServer
    module Routes
      # LogAggregator: /logs/services/:service/shards → shard_ids,
      #   /shards/:id/entries → log entries
      class Logs
        include Base

        def self.prefix = %r{^/(logs|shards)}

        def call(request)
          case request.path_info
          when %r{^/logs/services/([^/]+)/shards}
            json(200, shard_ids: %w[SH-1 SH-2])
          when %r{^/shards/([^/]+)/entries$}
            json(200, entries: [{level: "info", msg: "request handled"}])
          end
        end
      end
    end
  end
end
