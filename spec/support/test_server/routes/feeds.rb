require_relative "base"

module Support
  class TestServer
    module Routes
      # FeedIngestor: /feeds/:id/sources → source_urls,
      #   /src/:id → feed entries
      class Feeds
        include Base

        def self.prefix = %r{^/(feeds|src)}

        def call(request)
          case request.path_info
          when %r{^/feeds/([^/]+)/sources$}
            json(200, source_urls: %w[/src/1 /src/2])
          when %r{^/src/(\d+)$}
            json(200, entries: [{text: "hello", ts: 1_700_000_000}])
          end
        end
      end
    end
  end
end
