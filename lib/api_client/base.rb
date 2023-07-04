require_relative "configuration"
require_relative "connection"
require_relative "circuit"
require_relative "hooks"
require_relative "error"
require_relative "http_verbs"
require_relative "faraday_builder"
require_relative "orchestrators/sequential"
require_relative "orchestrators/batch"
require_relative "request_flow"

module ApiClient
  # Base API client with support for sequential, batch, and request flow execution
  #
  # Provides a Faraday-compatible interface while adding batch request
  # dispatch, circuit breaker, and request flow features.
  #
  # @example Simple usage (Faraday-style)
  #   client = ApiClient::Base.new(url: 'https://api.example.com')
  #   response = client.get('/users/1')
  #
  # @example With positional params (Faraday-style)
  #   client.get('/users', { page: 1 }, { 'X-Custom' => 'value' })
  #
  # @example With block configuration (Faraday-style)
  #   client = ApiClient::Base.new(url: 'https://api.example.com') do |config|
  #     config.read_timeout = 60
  #   end
  #
  # @example With request block (Faraday-style)
  #   client.get('/users') do |req|
  #     req.params['page'] = 1
  #     req.headers['X-Custom'] = 'value'
  #   end
  #
  # @example Batch requests (I/O-bound)
  #   responses = client.batch([
  #     { method: :get, path: '/users/1' },
  #     { method: :get, path: '/users/2' }
  #   ])
  #
  # @example RequestFlow (user → posts)
  #   posts = client.request_flow
  #     .fetch(:get, '/users/123')
  #     .then { |r| JSON.parse(r.body)['post_ids'] }
  #     .fan_out { |id| { method: :get, path: "/posts/#{id}" } }
  #     .collect
  #
  class Base
    extend HttpVerbs

    attr_reader :config, :connection, :circuit

    # @param url [String, nil] Base URL (Faraday-compatible alias for service_uri)
    # @param headers [Hash, nil] Default headers (Faraday-compatible alias for default_headers)
    # @param params [Hash, nil] Default params (Faraday-compatible alias for default_params)
    # @param overrides [Hash] Configuration overrides
    # @yield [Configuration] Optional block for configuration
    def initialize(url: nil, headers: nil, params: nil, **overrides, &block)
      normalize_url!(url, overrides) if url
      @config = build_config(overrides)
      # Faraday-compatible: headers/params merge with defaults (not replace)
      @config.default_headers = @config.default_headers.merge(headers) if headers
      @config.default_params = @config.default_params.merge(params) if params
      apply_faraday_block(@config, &block) if block
      @connection = Connection.new(@config)
      @circuit_name = build_circuit_name.freeze
      @circuit = Circuit.new(@circuit_name, @config.circuit_config)
    end

    # Faraday-compatible accessors
    # @return [URI] Base URL
    def url_prefix
      connection.base_uri
    end

    # @return [Hash] Default headers
    def headers
      config.default_headers
    end

    # @return [Hash] Default params
    def params
      config.default_params
    end

    # @return [Hash] Request options (timeouts)
    def options
      {
        open_timeout: config.open_timeout,
        read_timeout: config.read_timeout,
        write_timeout: config.write_timeout
      }
    end

    # HTTP verb methods with Faraday-compatible signatures
    #
    # Supports multiple calling conventions:
    #   client.get('/path')                              # simple
    #   client.get('/path', { page: 1 })                 # with params (positional)
    #   client.get('/path', { page: 1 }, { 'X-H' => 1 }) # params + headers
    #   client.get('/path', params: { page: 1 })         # keyword style
    #   client.get('/path') { |req| req.params['p'] = 1 } # block style
    #
    HttpVerbs::BODYLESS_VERBS.each do |verb|
      define_method(verb) do |path, params_or_opts = nil, headers_arg = nil, **opts, &block|
        params, headers = normalize_args(params_or_opts, headers_arg, opts, key: :params)
        with_circuit do
          connection.public_send(verb, path, params: params, headers: headers, &block)
        end
      end
    end

    # Body verb methods with Faraday-compatible signatures
    #
    # Supports multiple calling conventions:
    #   client.post('/path', { name: 'Bob' })            # body as positional
    #   client.post('/path', body: { name: 'Bob' })      # body as keyword
    #   client.post('/path') { |req| req.body = data }   # block style
    #
    HttpVerbs::BODY_VERBS.each do |verb|
      define_method(verb) do |path, body_or_opts = nil, headers_arg = nil, **opts, &block|
        body, headers = normalize_args(body_or_opts, headers_arg, opts, key: :body)
        with_circuit do
          connection.public_send(verb, path, body: body, headers: headers, &block)
        end
      end
    end

    # Execute batch of requests (uses best available adapter)
    # @param requests [Array<Hash>] Array of request hashes
    # @param adapter [Symbol, nil] Force specific adapter
    # @return [Array<Faraday::Response>]
    def batch(requests, adapter: nil)
      with_circuit do
        executor = Orchestrators::Batch.new(@config, adapter: adapter)
        executor.execute(requests)
      end
    end

    # Create a request flow for sequential-to-batch workflows
    # @param flow_timeout [Numeric, nil] Max seconds for entire flow (nil = no limit)
    # @return [RequestFlow]
    def request_flow(flow_timeout: nil)
      RequestFlow.new(@connection, flow_timeout: flow_timeout)
    end

    # Execute requests sequentially
    # @param requests [Array<Hash>] Array of request hashes
    # @return [Array<Faraday::Response>]
    def sequential(requests)
      with_circuit do
        executor = Orchestrators::Sequential.new(@connection)
        executor.execute(requests)
      end
    end

    # Check circuit breaker state
    # @return [Boolean] true if circuit is open (failing fast)
    def circuit_open?
      circuit.open?
    end

    # Reset circuit breaker
    def reset_circuit!
      circuit.reset!
    end

    # Current adapter being used for batch execution
    # @return [Symbol]
    def batch_adapter
      Backend.detect
    end

    # Available batch adapters
    # @return [Array<Symbol>]
    def available_adapters
      Backend.available
    end

    # Connection pool metrics for observability
    # @return [Hash] :size, :available, :type
    def pool_stats
      connection.pool_stats
    end

    private

    def build_config(overrides)
      global_config = ApiClient.configuration
      return global_config.dup if overrides.empty?

      global_config.merge(overrides)
    end

    # Extract path from url: into base_path when base_path is not explicitly set.
    # Faraday.new(url: "https://host/v1") preserves /v1 in url_prefix;
    # without this, our default base_path of "/" clobbers it via URI.join.
    def normalize_url!(url, overrides)
      parsed = URI.parse(url)
      path = parsed.path

      if !overrides.key?(:base_path) && path && path != "" && path != "/"
        # Split: origin goes to service_uri, path goes to base_path
        origin = "#{parsed.scheme}://#{parsed.host}"
        origin = "#{origin}:#{parsed.port}" unless default_port?(parsed)
        overrides[:service_uri] = origin
        overrides[:base_path] = path
      else
        overrides[:service_uri] = url
      end
    end

    def default_port?(uri)
      (uri.scheme == "https" && uri.port == 443) ||
        (uri.scheme == "http" && uri.port == 80) ||
        uri.port.nil?
    end

    def build_circuit_name
      uri = URI.parse(@config.service_uri)
      "api_client:#{uri.host}"
    end

    def with_circuit(&block)
      circuit.run(&block)
    end

    # Detect whether a block expects a Faraday-style builder or an ApiClient::Configuration.
    #
    # The block is called exactly once on a FaradayBuilder probe. The probe
    # captures both Faraday-style calls (request, response, adapter, options)
    # and Configuration-style attribute setters (via method_missing). After
    # the single call, captured settings are replayed onto the Configuration.
    def apply_faraday_block(config, &block)
      builder = FaradayBuilder.new
      block.call(builder)

      if builder.faraday_style?
        builder.apply_to(config)
      else
        # Configuration-style: replay captured setter calls on the real config
        builder.apply_config_calls(config)
      end
    end

    # Normalize arguments for bodyless verbs (GET, HEAD, DELETE, TRACE)
    # Supports: (path), (path, params), (path, params, headers), (path, params:, headers:)
    def normalize_args(positional, headers_arg, opts, key: :params)
      if positional.is_a?(Hash) && headers_arg.nil? && opts.empty?
        # Hash with recognized keys → keyword-style: client.get('/path', params: {...}, headers: {...})
        if positional.key?(key) || positional.key?(:headers)
          unknown = positional.keys - [key, :headers]
          unless unknown.empty?
            raise ArgumentError, I18n.t("base.unknown_keys", keys: unknown.inspect, expected: key)
          end
          [positional[key], positional[:headers] || {}]
        else
          # Plain hash → treat as the value itself (params or body)
          [positional, {}]
        end
      else
        [
          opts[key] || positional || ((key == :body) ? nil : {}),
          opts[:headers] || headers_arg || {}
        ]
      end
    end
  end
end
