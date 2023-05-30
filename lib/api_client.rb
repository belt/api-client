require "pathname"
require "zeitwerk"
require "active_support/notifications"
require "faraday"
require_relative "api_client/i18n"

# JIT activation is an application-level concern, not a library concern.
# Call ApiClient::JIT.activate AFTER all gems are loaded to eagerly load
# optional gems (pre-JIT) then enable YJIT (Ruby 3.1+).
# See lib/api_client/jit.rb for details.

# Zeitwerk loader setup
loader = Zeitwerk::Loader.for_gem

# Acronym inflections: Zeitwerk defaults jit → Jit, jwt → Jwt
loader.inflector.inflect("jit" => "JIT", "jwt" => "JWT")

# Backend system - loaded eagerly for registry
# Individual adapters are loaded on-demand based on available gems
loader.ignore("#{__dir__}/api_client/adapters")

# JWT support is optional - loaded on-demand when jwt gem available
loader.ignore("#{__dir__}/api_client/jwt")
loader.ignore("#{__dir__}/api_client/jwt.rb")

# Railtie only loads when Rails is present
loader.ignore("#{__dir__}/api_client/railtie.rb")

# Middlewares live outside the ApiClient namespace
loader.ignore("#{__dir__}/middlewares")

loader.setup

# ApiClient - HTTP client with concurrent requests and circuit breaker support
#
# @example Configuration
#   ApiClient.configure do |config|
#     config.service_uri = 'https://api.example.com'
#     config.open_timeout = 5
#     config.read_timeout = 30
#     config.on_error = :raise
#   end
#
# @example Simple usage
#   client = ApiClient::Base.new
#   response = client.get('/users/1')
#
# @example Concurrent requests (I/O-bound batching)
#   responses = client.concurrent([
#     { method: :get, path: '/users/1' },
#     { method: :get, path: '/users/2' }
#   ])
#
# @example RequestFlow (sequential → fan-out)
#   posts = client.request_flow
#     .fetch(:get, '/users/123')
#     .then { |r| JSON.parse(r.body)['post_ids'] }
#     .fan_out { |id| { method: :get, path: "/posts/#{id}" } }
#     .collect
#
module ApiClient
  # Gem project root, analogous to Rails.root.
  # Resolves to the directory containing Gemfile, config/, lib/, spec/, etc.
  PROJECT_ROOT = Pathname.new(File.expand_path("..", __dir__)).freeze

  # Namespace for concurrent HTTP adapters
  module Adapters; end

  # standard:disable ThreadSafety/ClassInstanceVariable
  @configuration_mutex = Mutex.new
  @configuration = nil

  class << self
    attr_reader :loader

    # @return [Pathname] Project root (like Rails.root)
    def root
      PROJECT_ROOT
    end

    # Global configuration
    # @return [Configuration]
    def configuration
      @configuration_mutex.synchronize do
        @configuration ||= Configuration.new
      end
    end

    # Configure ApiClient
    # @yield [Configuration]
    def configure
      yield(configuration)
    end

    # Reset configuration to defaults
    def reset_configuration!
      @configuration_mutex.synchronize do
        @configuration = Configuration.new
        @default_connection = nil
      end
    end

    # Create a new client (Faraday-compatible)
    #
    # @example Simple creation
    #   client = ApiClient.new(url: 'https://api.example.com')
    #
    # @example With block configuration (like Faraday)
    #   client = ApiClient.new(url: 'https://api.example.com') do |config|
    #     config.read_timeout = 60
    #     config.retry { |r| r.max = 3 }
    #   end
    #
    # @param url [String, nil] Base URL (Faraday-compatible alias for service_uri)
    # @param headers [Hash, nil] Default headers (Faraday-compatible alias)
    # @param params [Hash, nil] Default params (Faraday-compatible alias)
    # @param overrides [Hash] Configuration overrides
    # @yield [Configuration] Optional block for configuration
    # @return [Base]
    def new(url: nil, headers: nil, params: nil, **overrides, &block)
      Base.new(url: url, headers: headers, params: params, **overrides, &block)
    end

    # Module-level HTTP methods for one-off requests (Faraday-compatible)
    #
    # @example Simple GET
    #   response = ApiClient.get('https://api.example.com/users')
    #
    # @example POST with body
    #   response = ApiClient.post('https://api.example.com/users', name: 'Bob')
    #
    %i[get head delete trace].each do |verb|
      define_method(verb) do |url, params = {}, headers = {}, &block|
        default_connection.public_send(verb, url, params, headers, &block)
      end
    end

    %i[post put patch].each do |verb|
      define_method(verb) do |url, body = nil, headers = {}, &block|
        default_connection.public_send(verb, url, body, headers, &block)
      end
    end

    # Eager load all autoloadable constants
    def eager_load!
      loader.eager_load
    end

    # Default adapter for module-level requests
    # @return [Symbol]
    def default_adapter
      configuration.adapter
    end

    # Set default adapter
    # @param adapter [Symbol]
    def default_adapter=(adapter)
      configuration.adapter = adapter
    end

    private

    # Shared connection for module-level requests
    def default_connection
      @default_connection_mutex ||= Mutex.new
      @default_connection_mutex.synchronize do
        @default_connection ||= Base.new
      end
    end
  end

  @loader = loader
  # standard:enable ThreadSafety/ClassInstanceVariable
end

# Load Rails integration when Rails is present
require_relative "api_client/railtie" if defined?(Rails::Railtie)
