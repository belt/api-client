require "json"
require "rack"
require "stringio"

Dir[File.join(__dir__, "routes", "*.rb")].each { |f| require f }

module Support
  class MockApi
    attr_reader :base_url

    def initialize
      @base_url = "https://api.example.test"
      @router = Router.new
      @requests = []
      @mutex = Mutex.new
    end

    def requests
      @mutex.synchronize { @requests.dup }
    end

    def clear_requests
      @mutex.synchronize { @requests.clear }
    end

    def call(request)
      uri = request.uri
      @mutex.synchronize do
        path = uri.query ? "#{uri.path}?#{uri.query}" : uri.path
        @requests << {method: request.method, path: path}
      end

      env = Rack::MockRequest.env_for(uri.to_s,
        method: request.method.to_s.upcase,
        input: request.body.to_s)
      request.headers.each do |name, value|
        env_key = if name.casecmp("content-type").zero?
          "CONTENT_TYPE"
        elsif name.casecmp("content-length").zero?
          "CONTENT_LENGTH"
        else
          "HTTP_#{name.upcase.tr("-", "_")}"
        end
        env[env_key] = Array(value).join(", ")
      end

      status, headers, body = @router.call(Rack::Request.new(env))
      {status: status, headers: headers, body: body.join}
    end

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
