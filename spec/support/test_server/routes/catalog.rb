require_relative "base"

module Support
  class TestServer
    module Routes
      # CatalogSearcher: /catalog/providers → provider_ids,
      #   /catalog/providers/:id/search → results
      class Catalog
        include Base

        def self.prefix = %r{^/catalog}

        def call(request)
          case request.path_info
          when %r{^/catalog/providers$}
            json(200, provider_ids: %w[P-1 P-2])
          when %r{^/catalog/providers/([^/]+)/search$}
            json(200, results: [{title: "Ruby Programming"}])
          end
        end
      end
    end
  end
end
