require "json"

Dir[File.join(__dir__, "routes", "*.rb")].each { |f| require f }

module Support
  class TestServer
    # Routes incoming requests to the first matching route module.
    #
    # More-specific routes (HealthClusters, Profiles) are registered before
    # broader ones (Core) so that `/health/clusters/...` and `/users/segments/...`
    # don't fall through to Core's `/health` and `/users` handlers.
    class Router
      JSON_CONTENT_TYPE = {"content-type" => "application/json"}.freeze

      # Order matters: specific prefixes before broad ones.
      ROUTE_CLASSES = [
        Routes::HealthClusters,
        Routes::Profiles,
        Routes::Core,
        Routes::Orders,
        Routes::Catalog,
        Routes::Compliance,
        Routes::Legacy,
        Routes::Feeds,
        Routes::Notifications,
        Routes::Config,
        Routes::Media,
        Routes::Routing,
        Routes::Registry,
        Routes::Payments,
        Routes::Logs,
        Routes::Metrics,
        Routes::Reports
      ].freeze

      def initialize
        @routes = ROUTE_CLASSES.map { |klass| [klass.prefix, klass.new] }.freeze
      end

      def call(request)
        @routes.each do |prefix, handler|
          next unless request.path_info.match?(prefix)

          result = handler.call(request)
          return result if result
        end

        [404, JSON_CONTENT_TYPE, [{error: "Not found"}.to_json]]
      end
    end
  end
end
