require "faraday/retry"
require_relative "http_verbs"
require_relative "response_builder"
require_relative "concerns/poolable"

begin
  require "faraday/typhoeus"
rescue LoadError
  # typhoeus adapter not available
end

module ApiClient
  # Request builder for Faraday-style block customization
  #
  # @example
  #   client.get('/users') do |req|
  #     req.params['page'] = 1
  #     req.headers['X-Custom'] = 'value'
  #   end
  #
  class RequestBuilder
    attr_accessor :params, :headers, :body

    def initialize(params = {}, headers = {}, body = nil)
      @params = params.dup
      @headers = headers.dup
      @body = body
    end

    # Set the request URL/path (Faraday compatibility)
    def url(path)
      @path = path
    end
  end

  # Faraday connection builder with timeout configuration
  #
  # Handles connection creation, middleware setup, and pooling.
  # Returns raw Faraday::Response for transparency.
  #
  class Connection
    include Concerns::Poolable

    attr_reader :config

    # @param config [Configuration] Configuration instance
    def initialize(config = ApiClient.configuration)
      @config = config
      @pool = build_pool(config.pool_config) { build_connection }
    end

    # Yield a Faraday connection for introspection (e.g. checking middleware).
    #
    # The connection is checked out from the pool for the duration of the
    # block and returned automatically. This avoids leaking a pooled
    # connection outside its checkout lifecycle.
    #
    # @yield [Faraday::Connection] Checked-out connection
    # @return [Object] Block result
    #
    # @example Inspect middleware
    #   connection.with_faraday { |f| f.builder.handlers }
    #
    def with_faraday(&block)
      with_pooled_connection(&block)
    end

    # Execute a request, returning Faraday::Response
    # @param method [Symbol] HTTP method
    # @param path [String] Request path
    # @param params [Hash] Query parameters
    # @param headers [Hash] Request headers
    # @param body [Object] Request body
    # @yield [RequestBuilder] Optional block for request customization (Faraday-style)
    # @return [Faraday::Response]
    def request(method, path, params: {}, headers: {}, body: nil, &block)
      url = full_url(path)
      Hooks.instrument(:request_start, method: method, url: url, headers: headers)

      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      response = execute_request(method:, path:, params:, headers:, body:, &block)
      duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time

      Hooks.instrument(:request_complete,
        method: method, url: url,
        status: response.status, duration: duration)
      response
    rescue Faraday::Error, Timeout::Error, Errno::ECONNREFUSED => error
      Hooks.instrument(:request_error, method: method, url: url, error: error)
      handle_error(error)
    end

    HttpVerbs::BODYLESS_VERBS.each do |verb|
      define_method(verb) do |path, params: HttpVerbs::EMPTY_HASH, headers: HttpVerbs::EMPTY_HASH, &block|
        request(verb, path, params: params, headers: headers, &block)
      end
    end

    HttpVerbs::BODY_VERBS.each do |verb|
      define_method(verb) do |path, body: nil, params: HttpVerbs::EMPTY_HASH, headers: HttpVerbs::EMPTY_HASH, &block|
        request(verb, path, params: params, headers: headers, body: body, &block)
      end
    end

    def base_uri
      @base_uri ||= URI.join(config.service_uri, config.base_path)
    end

    # Pool utilization metrics for observability
    # @return [Hash] :size, :available, :type
    def pool_stats
      {
        size: @pool.size,
        available: @pool.available,
        type: @pool.is_a?(ConnectionPool) ? :connection_pool : :null_pool
      }
    end

    private

    def execute_request(method:, path:, params:, headers:, body:, &block)
      with_pooled_connection do |faraday|
        if block
          builder = RequestBuilder.new(params, headers, body)
          block.call(builder)
          faraday.run_request(method, path, builder.body, builder.headers) do |req|
            req.params.update(builder.params)
          end
        else
          faraday.run_request(method, path, body, headers) do |req|
            req.params.update(params) unless params.empty?
          end
        end
      end
    end

    def full_url(path)
      uri = URI.join(base_uri, path)
      UriPolicy.validate!(uri, config)
      uri.to_s
    rescue SsrfBlockedError => error
      Hooks.instrument(:request_blocked, url: uri.to_s, reason: error.reason)
      raise
    end

    def build_connection
      Faraday.new(url: base_uri, **config.to_faraday_options) do |faraday|
        configure_request(faraday)
        configure_retry(faraday)
        configure_logging(faraday)
        configure_adapter(faraday)
      end
    end

    def configure_request(faraday)
      # Middleware order matters: :url_encoded runs first for form-encoded
      # bodies, then :json encodes Hash bodies as JSON (checking Content-Type).
      # A Hash body with Content-Type: application/json is handled by :json;
      # :url_encoded only acts on application/x-www-form-urlencoded requests.
      faraday.request :url_encoded
      faraday.request :json

      faraday.headers.update(config.default_headers)
      faraday.params.update(config.default_params)
    end

    def configure_retry(faraday)
      faraday.request :retry, config.retry_config.to_h
    end

    def configure_logging(faraday)
      return unless config.log_requests

      faraday.response :logger, config.logger, bodies: config.log_bodies do |logger|
        logger.filter(/(authorization\s*:\s*)(?:"|')?(?:.*?)(?:'|")?.*/i, '\1[REDACTED]')
      end
    end

    def configure_adapter(faraday)
      faraday.adapter(config.adapter)
    end

    def handle_error(error)
      case config.on_error
      when :return
        build_error_response(error)
      when :log_and_return
        config.logger.error { I18n.t("connection.error_log", message: error.message) }
        build_error_response(error)
      else # :raise or unknown
        raise error
      end
    end

    # Wrap an error in a synthetic Faraday::Response so callers can
    # safely chain .status / .body regardless of on_error strategy.
    # @param error [Exception]
    # @return [Faraday::Response]
    def build_error_response(error)
      ResponseBuilder.error_response(error)
    end
  end
end
