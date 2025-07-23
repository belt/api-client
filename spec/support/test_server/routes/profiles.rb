require_relative "base"

module Support
  class TestServer
    module Routes
      # UserEnricher: /users/segments/:id/members → user_ids,
      #   /profiles/:id → enriched profile
      #
      # Note: /users/segments is more specific than Core's /users/:id,
      # so this route module is checked before Core.
      class Profiles
        include Base

        def self.prefix = %r{^/(users/segments|profiles)}

        def call(request)
          case request.path_info
          when %r{^/users/segments/([^/]+)/members$}
            json(200, user_ids: %w[U-1 U-2 U-3])
          when %r{^/profiles/([^/]+)$}
            json(200, name: "Jane Doe", email: "[email]")
          end
        end
      end
    end
  end
end
