module ApiClient
  module Jwt
    # Request authenticator for Bearer token injection
    #
    # Provides headers hash or Faraday middleware for adding
    # JWT Bearer tokens to outgoing requests.
    #
    # @example Static token
    #   auth = ApiClient::Jwt::Authenticator.new(token_provider: "eyJ...")
    #   client = ApiClient.new(default_headers: auth.headers)
    #
    # @example Dynamic token (refreshed per-request)
    #   auth = ApiClient::Jwt::Authenticator.new(
    #     token_provider: -> { generate_fresh_token }
    #   )
    #
    # @example With Token instance
    #   signer = ApiClient::Jwt::Token.new(algorithm: "RS256", key: private_key)
    #   auth = ApiClient::Jwt::Authenticator.new(
    #     token_provider: -> { signer.encode({ sub: "service" }) }
    #   )
    #
    class Authenticator
      DEFAULT_HEADER = "Authorization"
      DEFAULT_SCHEME = "Bearer"

      attr_reader :header_name, :scheme

      # @param token_provider [String, Proc, #call] Token or callable returning token
      # @param header_name [String] Header name (default: Authorization)
      # @param scheme [String] Auth scheme (default: Bearer)
      def initialize(token_provider:, header_name: DEFAULT_HEADER, scheme: DEFAULT_SCHEME)
        @token_provider = token_provider
        @header_name = header_name.freeze
        @scheme = scheme.freeze

        # Cache the token resolver strategy at initialization
        @resolver = build_resolver
      end

      # Get headers hash with current token
      # @return [Hash]
      def headers
        {@header_name => authorization_value}
      end

      # Get just the authorization header value
      # @return [String]
      def authorization_value
        "#{@scheme} #{@resolver.call}"
      end

      # Get current token (without scheme)
      # @return [String]
      def token
        @resolver.call
      end

      # Create Faraday middleware class (memoized per argument set)
      #
      # Returns the same anonymous class for identical arguments so
      # callers in hot paths don't generate unbounded anonymous classes.
      #
      # @return [Class<Faraday::Middleware>]
      # Class instance variables below are intentional: mutex-guarded memoization cache for middleware classes.
      def self.middleware(token_provider:, **options)
        @middleware_cache_mutex ||= Mutex.new # standard:disable ThreadSafety/ClassInstanceVariable
        cache_key = [token_provider, options].freeze

        @middleware_cache_mutex.synchronize do
          @middleware_cache ||= {} # standard:disable ThreadSafety/ClassInstanceVariable
          @middleware_cache[cache_key] ||= begin
            authenticator = new(token_provider: token_provider, **options)

            Class.new(Faraday::Middleware) do
              define_method(:initialize) do |app|
                super(app)
                @authenticator = authenticator
              end

              define_method(:call) do |env|
                env.request_headers[@authenticator.header_name] = @authenticator.authorization_value
                @app.call(env)
              end
            end
          end
        end
      end

      private

      def build_resolver
        case @token_provider
        when String
          token = @token_provider
          -> { token }
        when Proc
          @token_provider
        else
          if @token_provider.respond_to?(:call)
            -> { @token_provider.call }
          else
            token = @token_provider.to_s
            -> { token }
          end
        end
      end
    end
  end
end
