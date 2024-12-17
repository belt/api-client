require "api_client/backend"
require "api_client/adapters/base"
require "net/http"
require "json"

module ApiClient
  module Examples
    # Net::HTTP backend implementation
    #
    # Demonstrates the Backend::Registry plugin system with a complete
    # Net::HTTP backend. This backend uses Ruby's standard library
    # Net::HTTP directly without any external dependencies.
    #
    # Custom backends must implement the Backend::Interface contract:
    # - #execute(requests) → Array<Faraday::Response>
    # - #config → Configuration
    #
    # @example Register and use Net::HTTP backend
    #   ApiClient::Examples::NetHttp.register!
    #   client = ApiClient::Base.new(adapter: :net_http)
    #   response = client.get('/users')
    #
    class NetHttp
      # Net::HTTP backend using Ruby standard library
      class Backend
        include ApiClient::Backend::Interface
        include ApiClient::Adapters::Base

        attr_reader :config

        def initialize(config = ApiClient.configuration)
          @config = config
          @base_uri = URI.join(config.service_uri, config.base_path)
        end

        # Execute requests sequentially using Net::HTTP
        # @param requests [Array<Hash>] Request specifications
        # @return [Array<Faraday::Response>]
        def execute(requests)
          requests.map { |req| execute_single(req) }
        end

        private

        def execute_single(request)
          uri = build_uri(request[:path], request[:params])
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = (uri.scheme == "https")
          http.open_timeout = config.open_timeout
          http.read_timeout = config.read_timeout

          net_request = build_net_request(request, uri)
          response = http.request(net_request)

          build_faraday_response(
            status: response.code.to_i,
            headers: response.each_header.to_h,
            body: response.body,
            url: uri.to_s
          )
        rescue => error
          build_error_response(error, uri)
        end

        def build_uri(path, params)
          # Concatenate base_path + path (URI.join replaces path for absolute paths)
          full_path = File.join(@base_uri.path, path)
          uri = @base_uri.dup
          uri.path = full_path
          if params && !params.empty?
            uri.query = URI.encode_www_form(params)
          end
          uri
        end

        def build_net_request(request, uri)
          klass = case request[:method]
          when :get then Net::HTTP::Get
          when :post then Net::HTTP::Post
          when :put then Net::HTTP::Put
          when :patch then Net::HTTP::Patch
          when :delete then Net::HTTP::Delete
          when :head then Net::HTTP::Head
          else Net::HTTP::Get
          end

          net_request = klass.new(uri)

          # Merge headers
          merged_headers(request[:headers]).each do |key, value|
            net_request[key] = value
          end

          # Set body for methods that support it
          if request[:body] && net_request.request_body_permitted?
            net_request.body = encode_body(request[:body])
          end

          net_request
        end
      end

      # Register the Net::HTTP backend
      def self.register!
        ApiClient::Backend.register(:net_http, Backend)
      end

      # Example usage
      def self.demo
        register!

        client = ApiClient::Base.new(
          url: "https://api.example.com",
          adapter: :net_http
        )

        response = client.get("/users/1")
        puts "Status: #{response.status}"
        puts "Body: #{response.body}"
      end
    end
  end
end
