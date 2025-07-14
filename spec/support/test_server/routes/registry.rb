require_relative "base"

module Support
  class TestServer
    module Routes
      # DepGraphBuilder: /registry/packages/:name/dependencies → dep_names,
      #   /registry/packages/:name/metadata → package metadata
      class Registry
        include Base

        def self.prefix = %r{^/registry}

        def call(request)
          case request.path_info
          when %r{^/registry/packages/([^/]+)/dependencies$}
            json(200, dep_names: %w[faraday concurrent-ruby])
          when %r{^/registry/packages/([^/]+)/metadata$}
            name = request.path_info[%r{/packages/([^/]+)/metadata}, 1]
            json(200, name: name, version: "2.9.0")
          end
        end
      end
    end
  end
end
