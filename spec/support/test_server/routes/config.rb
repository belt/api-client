require_relative "base"

module Support
  class TestServer
    module Routes
      # ConfigSnapshot: /config/apps/:app/environments → environment_ids,
      #   /config/apps/:app/environments/:env/snapshot → config snapshot
      class Config
        include Base

        def self.prefix = %r{^/config}

        def call(request)
          case request.path_info
          when %r{^/config/apps/([^/]+)/environments$}
            json(200, environment_ids: %w[dev staging prod])
          when %r{^/config/apps/([^/]+)/environments/([^/]+)/snapshot$}
            json(200, db_host: "db.local", cache_ttl: 300)
          end
        end
      end
    end
  end
end
