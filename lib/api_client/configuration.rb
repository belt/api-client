require "active_support/core_ext/hash/deep_merge"
require "etc"
require "ipaddr"

module ApiClient
  # Configuration DSL for ApiClient
  #
  # @example Global configuration
  #   ApiClient.configure do |config|
  #     config.service_uri = 'https://api.example.com'
  #     config.open_timeout = 5
  #     config.read_timeout = 30
  #   end
  #
  # @example Per-instance override
  #   client = ApiClient::Base.new(read_timeout: 60)
  #
  class Configuration
    # Nested config keys mapped to their accessor methods
    NESTED_CONFIGS = {retry: :retry_config, circuit: :circuit_config, jwt: :jwt_config, pool: :pool_config}.freeze

    # Connection settings
    attr_accessor :service_uri, :base_path, :adapter

    # Timeout settings (separate granularity)
    attr_accessor :open_timeout, :read_timeout, :write_timeout

    # Request defaults
    attr_accessor :default_headers, :default_params

    # Logging
    attr_accessor :logger, :log_requests, :log_bodies

    # Error handling: :raise | :return | :log_and_return
    attr_accessor :on_error

    # Processor configuration (ractor, async, concurrent)
    attr_reader :processor_config

    # Connection pool configuration
    attr_reader :pool_config

    # Slow request threshold (ms) for batch operations
    attr_accessor :batch_slow_threshold_ms

    # Maximum timeout (ms) for fan-out requests (ceiling to prevent misconfiguration)
    attr_accessor :fan_out_max_timeout_ms

    # URI policy: SSRF protection
    # @return [Boolean] Enable/disable URI validation (default: true)
    attr_accessor :uri_policy_enabled

    # @return [Array<String>] Allowed host patterns (empty = allow all non-blocked)
    #   Supports wildcard prefix: "*.example.com"
    attr_accessor :allowed_hosts

    # @return [Array<String>] Additional blocked host patterns
    attr_accessor :blocked_hosts

    # @return [Array<String>] Blocked URI schemes (default: file, ftp, data, javascript)
    attr_accessor :blocked_schemes

    # @return [Array<IPAddr>] Blocked IP networks for SSRF prevention
    #   Defaults to RFC 1918 + link-local + loopback
    attr_accessor :blocked_networks

    # @return [Regexp] Pattern used to detect path traversal attempts
    attr_accessor :path_traversal_pattern

    # Retry configuration (delegated to faraday-retry)
    attr_reader :retry_config

    # Circuit breaker configuration (delegated to stoplight)
    attr_reader :circuit_config

    # JWT configuration (optional, requires jwt gem)
    attr_reader :jwt_config

    # Frozen empty array returned from hooks_for when no hooks registered.
    # Avoids mutex acquire + dup + freeze on every Hooks.instrument call
    # (hot path: 2-3 calls per request).
    EMPTY_HOOKS = [].freeze
    private_constant :EMPTY_HOOKS

    # Custom hooks registry (thread-safe)
    # @return [Hash] Snapshot of registered hooks
    def hooks
      @hooks_mutex.synchronize { @hooks.dup }
    end

    # Fast check for whether any custom hooks are registered.
    # Used by Hooks.instrument to skip block overhead when no hooks exist.
    # @return [Boolean]
    def has_hooks?
      @has_hooks
    end

    def initialize
      set_defaults
      @processor_config = ProcessorConfig.new
      @pool_config = PoolConfig.new
      @retry_config = RetryConfig.new
      @circuit_config = CircuitConfig.new
      @jwt_config = JwtConfig.new
      @hooks_mutex = Mutex.new
      @hooks = {}
      @has_hooks = false
    end

    def retry
      yield(@retry_config) if block_given?
      @retry_config
    end

    def circuit
      yield(@circuit_config) if block_given?
      @circuit_config
    end

    def jwt
      yield(@jwt_config) if block_given?
      @jwt_config
    end

    def pool
      yield(@pool_config) if block_given?
      @pool_config
    end

    # Register a hook for an event
    # @param event [Symbol] Event name (e.g., :request_start, :request_complete)
    # @param block [Proc] Handler block
    def on(event, &block)
      return unless block_given?

      @hooks_mutex.synchronize do
        (@hooks[event] ||= []) << block
        @has_hooks = true
      end
    end

    # Thread-safe hook lookup
    # @param event [Symbol] Event name
    # @return [Array<Proc>] Registered hooks (frozen snapshot)
    def hooks_for(event)
      # Fast path: no hooks registered at all (common case).
      # Avoids mutex acquire + hash lookup + dup + freeze per call.
      return EMPTY_HOOKS unless @has_hooks

      @hooks_mutex.synchronize do
        (@hooks[event] || EMPTY_HOOKS).dup.freeze
      end
    end

    # Merge with overrides for per-instance configuration
    #
    # Deep-duplicates nested config objects (RetryConfig, CircuitConfig, etc.)
    # so mutations on the returned copy never affect the original.
    #
    # @param overrides [Hash] Override values
    # @return [Configuration] New configuration with overrides applied
    def merge(overrides = {})
      deep_dup.tap do |new_config|
        overrides.each do |key, value|
          apply_override(new_config, key, value)
        end
      end
    end

    # Convert to Faraday-compatible options hash
    def to_faraday_options
      {
        request: {
          open_timeout: open_timeout,
          read_timeout: read_timeout,
          write_timeout: write_timeout
        }
      }
    end

    private

    def apply_override(target, key, value)
      nested_accessor = NESTED_CONFIGS[key]
      if nested_accessor
        nested = target.public_send(nested_accessor)
        value.each do |attr, val|
          nested.public_send(:"#{attr}=", val)
        end
      elsif target.respond_to?(:"#{key}=")
        target.public_send(:"#{key}=", value)
      end
    end

    # Instance variables that hold nested config objects (must be .dup'd)
    NESTED_CONFIG_IVARS = %i[
      @processor_config @pool_config @retry_config @circuit_config @jwt_config
    ].freeze

    # Instance variables that hold mutable collections (must be .dup'd)
    MUTABLE_COLLECTION_IVARS = %i[
      @default_headers @default_params @allowed_hosts
      @blocked_hosts @blocked_schemes @blocked_networks
    ].freeze

    # Deep-duplicate: dup + replace nested config objects and mutable collections
    # so the copy is fully independent of the original.
    #
    # Mutex#dup raises TypeError on Ruby 3.x, so we explicitly replace
    # @hooks_mutex with a fresh Mutex.new. Hooks should not be shared
    # across config instances regardless.
    #
    # Add new nested configs to NESTED_CONFIG_IVARS and new mutable
    # collections to MUTABLE_COLLECTION_IVARS — this method picks them
    # up automatically.
    def deep_dup
      dup.tap do |copy|
        NESTED_CONFIG_IVARS.each do |ivar|
          copy.instance_variable_set(ivar, instance_variable_get(ivar).dup)
        end

        MUTABLE_COLLECTION_IVARS.each do |ivar|
          copy.instance_variable_set(ivar, instance_variable_get(ivar).dup)
        end

        # Fresh hooks and mutex — hooks should never be shared across
        # config instances.
        copy.instance_variable_set(:@hooks_mutex, Mutex.new)
        copy.instance_variable_set(:@hooks, {})
        copy.instance_variable_set(:@has_hooks, false)
      end
    end

    def set_defaults
      set_connection_defaults
      set_request_defaults
      set_logging_defaults
      @on_error = :raise
      @batch_slow_threshold_ms = 5000
      @fan_out_max_timeout_ms = 600_000
      @uri_policy_enabled = true
      @allowed_hosts = []
      @blocked_hosts = []
      @blocked_schemes = %w[file ftp data javascript].freeze
      @blocked_networks = default_blocked_networks
      @path_traversal_pattern = /(?:^|\/)\.\.\//
    end

    def set_connection_defaults
      @service_uri = "http://localhost:8080"
      @base_path = "/"
      @adapter = detect_default_adapter
      @open_timeout = 5
      @read_timeout = 30
      @write_timeout = 10
    end

    def set_request_defaults
      @default_headers = {
        "Accept" => "application/json",
        "Content-Type" => "application/json"
      }
      @default_params = {}
    end

    def set_logging_defaults
      @logger = default_logger
      @log_requests = env_bool("API_CLIENT_LOG_REQUESTS", false)
      @log_bodies = env_bool("API_CLIENT_LOG_BODIES", false)
    end

    def detect_default_adapter
      if defined?(::Typhoeus)
        :typhoeus
      elsif defined?(::NetHTTPPersistent)
        :net_http_persistent
      else
        :net_http
      end
    end

    def default_logger
      if defined?(::Rails) && ::Rails.respond_to?(:logger) && ::Rails.logger
        ::Rails.logger
      else
        Logger.new($stderr, level: Logger::WARN)
      end
    end

    def env_bool(key, default)
      val = ENV.fetch(key) { return default }
      %w[true 1 yes].include?(val.to_s.downcase)
    end

    # RFC 1918 + link-local + loopback networks blocked by default,
    # plus cloud-specific metadata IPs not in standard private ranges.
    def default_blocked_networks
      %w[
        10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 169.254.0.0/16
        127.0.0.0/8 0.0.0.0/8 ::1/128 fc00::/7 fe80::/10
        100.100.100.200/32
        192.0.0.192/32
      ].map { |cidr| IPAddr.new(cidr) }.freeze
    end
  end

  # Processor configuration for ractor, async, and concurrent processors
  class ProcessorConfig
    # Ractor processing settings
    attr_reader :ractor_pool_size, :ractor_min_batch_size,
      :ractor_min_payload_size

    # AsyncProcessor settings (fork-based parallelism)
    attr_reader :async_pool_size, :async_min_batch_size,
      :async_min_payload_size

    # ConcurrentProcessor settings (thread-based parallelism)
    attr_reader :concurrent_processor_pool_size, :concurrent_processor_min_batch_size

    def initialize
      cpus = Etc.nprocessors

      @ractor_pool_size = cpus
      @ractor_min_batch_size = 4
      @ractor_min_payload_size = 4096

      @async_pool_size = cpus
      @async_min_batch_size = 4
      @async_min_payload_size = 4096

      @concurrent_processor_pool_size = cpus
      @concurrent_processor_min_batch_size = 4
    end

    %i[ractor_pool_size async_pool_size concurrent_processor_pool_size].each do |attr|
      define_method(:"#{attr}=") do |value|
        raise ConfigurationError, ApiClient::I18n.t("configuration.positive_integer", attribute: attr, value: value.inspect) unless value.is_a?(Integer) && value > 0
        instance_variable_set(:"@#{attr}", value)
      end
    end

    %i[ractor_min_batch_size async_min_batch_size concurrent_processor_min_batch_size].each do |attr|
      define_method(:"#{attr}=") do |value|
        raise ConfigurationError, ApiClient::I18n.t("configuration.non_negative_integer", attribute: attr, value: value.inspect) unless value.is_a?(Integer) && value >= 0
        instance_variable_set(:"@#{attr}", value)
      end
    end

    %i[ractor_min_payload_size async_min_payload_size].each do |attr|
      define_method(:"#{attr}=") do |value|
        raise ConfigurationError, ApiClient::I18n.t("configuration.non_negative_integer", attribute: attr, value: value.inspect) unless value.is_a?(Integer) && value >= 0
        instance_variable_set(:"@#{attr}", value)
      end
    end
  end

  # Connection pool configuration
  #
  # Controls ConnectionPool settings for Faraday connections and
  # adapter connections. Lazy creation means pool_size can be generous
  # without wasting memory.
  #
  # @example Configure pool
  #   ApiClient.configure do |config|
  #     config.pool do |p|
  #       p.size = 10
  #       p.timeout = 5
  #     end
  #   end
  #
  class PoolConfig
    # Max connections in pool (lazy-created)
    attr_reader :size

    # Seconds to wait for checkout before raising ConnectionPool::TimeoutError
    attr_reader :timeout

    # Enable/disable pooling (true by default when connection_pool gem available)
    attr_accessor :enabled

    def initialize
      @size = Etc.nprocessors
      @timeout = 5
      @enabled = true
    end

    def size=(value)
      raise ConfigurationError, ApiClient::I18n.t("configuration.pool_size_positive", value: value.inspect) unless value.is_a?(Integer) && value > 0
      @size = value
    end

    def timeout=(value)
      raise ConfigurationError, ApiClient::I18n.t("configuration.pool_timeout_positive", value: value.inspect) unless value.is_a?(Numeric) && value > 0
      @timeout = value
    end

    def to_h
      {size: size, timeout: timeout, enabled: enabled}
    end
  end

  # Retry configuration (delegates to faraday-retry)
  class RetryConfig
    attr_reader :max, :interval, :interval_randomness, :backoff_factor,
      :retry_statuses, :methods, :exceptions

    def initialize
      @max = 2
      @interval = 0.5
      @interval_randomness = 0.5
      @backoff_factor = 2
      @retry_statuses = [429, 500, 502, 503, 504].freeze
      @methods = %i[get head put delete options trace].freeze
      @exceptions = default_exceptions.freeze
    end

    def max=(value)
      raise ConfigurationError, I18n.t("configuration.non_negative_integer", attribute: :max, value: value.inspect) unless value.is_a?(Integer) && value >= 0
      @max = value
    end

    def interval=(value)
      raise ConfigurationError, I18n.t("configuration.pool_timeout_positive", value: value.inspect) unless value.is_a?(Numeric) && value > 0
      @interval = value
    end

    def interval_randomness=(value)
      raise ConfigurationError, I18n.t("configuration.non_negative_numeric", attribute: :interval_randomness, value: value.inspect) unless value.is_a?(Numeric) && value >= 0
      @interval_randomness = value
    end

    def backoff_factor=(value)
      raise ConfigurationError, I18n.t("configuration.positive_numeric", attribute: :backoff_factor, value: value.inspect) unless value.is_a?(Numeric) && value > 0
      @backoff_factor = value
    end

    def retry_statuses=(value)
      raise ConfigurationError, I18n.t("configuration.must_be_array", attribute: :retry_statuses, value: value.inspect) unless value.is_a?(Array)
      @retry_statuses = value
    end

    def methods=(value)
      raise ConfigurationError, I18n.t("configuration.must_be_array", attribute: :methods, value: value.inspect) unless value.is_a?(Array)
      @methods = value
    end

    def exceptions=(value)
      raise ConfigurationError, I18n.t("configuration.must_be_array", attribute: :exceptions, value: value.inspect) unless value.is_a?(Array)
      @exceptions = value
    end

    # Convert to faraday-retry options hash.
    # When max is zero all retry behavior is disabled: statuses and
    # exceptions are cleared so faraday-retry becomes a no-op.
    def to_h
      disabled = max.zero?
      {
        max: max,
        interval: interval,
        interval_randomness: interval_randomness,
        backoff_factor: backoff_factor,
        retry_statuses: disabled ? [] : retry_statuses,
        methods: disabled ? [] : methods,
        exceptions: disabled ? [] : exceptions
      }.freeze
    end

    private

    def default_exceptions
      exceptions = [
        Errno::ETIMEDOUT,
        Timeout::Error
      ]
      # Add Faraday exceptions only if Faraday is loaded
      if defined?(Faraday)
        exceptions << Faraday::TimeoutError
        exceptions << Faraday::ConnectionFailed
      end
      exceptions
    end
  end

  # Circuit breaker configuration (delegates to stoplight)
  class CircuitConfig
    attr_reader :threshold, :cool_off, :data_store, :redis_client,
      :window_size, :tracked_errors, :redis_pool
    attr_accessor :enabled

    def initialize
      @enabled = true
      @threshold = 5
      @cool_off = 30
      @data_store = :memory
      @redis_client = nil
      @redis_pool = nil
      @window_size = nil # nil = count all failures, Integer = sliding window in seconds
      @tracked_errors = nil # nil = all errors, Array = specific error classes
    end

    def threshold=(value)
      raise ConfigurationError, I18n.t("configuration.positive_integer", attribute: :threshold, value: value.inspect) unless value.is_a?(Integer) && value > 0
      @threshold = value
    end

    def cool_off=(value)
      raise ConfigurationError, I18n.t("configuration.positive_numeric", attribute: :cool_off, value: value.inspect) unless value.is_a?(Numeric) && value > 0
      @cool_off = value
    end

    def data_store=(value)
      raise ConfigurationError, I18n.t("configuration.invalid_data_store", value: value.inspect) unless %i[memory redis].include?(value)
      @data_store = value
    end

    attr_writer :redis_client

    attr_writer :redis_pool

    def window_size=(value)
      if !value.nil? && !(value.is_a?(Numeric) && value > 0)
        raise ConfigurationError, I18n.t("configuration.positive_numeric_or_nil", attribute: :window_size, value: value.inspect)
      end
      @window_size = value
    end

    def tracked_errors=(value)
      unless value.nil? || value.is_a?(Array)
        raise ConfigurationError, I18n.t("configuration.must_be_array_or_nil", attribute: :tracked_errors, value: value.inspect)
      end
      @tracked_errors = value
    end

    # Only track specific error types
    # @param errors [Array<Class>] Error classes to track
    def track_only(*errors)
      @tracked_errors = errors.flatten
    end

    def to_h
      {
        enabled: enabled,
        threshold: threshold,
        cool_off: cool_off,
        data_store: data_store,
        window_size: window_size,
        tracked_errors: tracked_errors&.map(&:name)
      }.freeze
    end
  end

  # JWT configuration (optional, requires jwt gem)
  #
  # @example Configure JWT settings
  #   ApiClient.configure do |config|
  #     config.jwt do |jwt|
  #       jwt.algorithm = "RS256"
  #       jwt.issuer = "https://auth.example.com"
  #       jwt.audience = "my-api"
  #       jwt.jwks_uri = "https://auth.example.com/.well-known/jwks.json"
  #     end
  #   end
  #
  class JwtConfig
    # Default signing/verification algorithm
    attr_accessor :algorithm

    # Token issuer (iss claim)
    attr_accessor :issuer

    # Token audience (aud claim)
    attr_accessor :audience

    # JWKS endpoint URI for key retrieval
    attr_accessor :jwks_uri

    # JWKS cache TTL in seconds
    attr_accessor :jwks_ttl

    # Default token lifetime in seconds
    attr_accessor :token_lifetime

    # Allowed algorithms for verification
    attr_accessor :allowed_algorithms

    # Allow HMAC algorithms (not recommended for API-to-API)
    attr_accessor :allow_hmac

    # Clock skew tolerance in seconds
    attr_accessor :leeway

    def initialize
      @algorithm = "RS256"
      @issuer = nil
      @audience = nil
      @jwks_uri = nil
      @jwks_ttl = 600
      @token_lifetime = 900
      @allowed_algorithms = %w[RS256 RS384 RS512 ES256 ES384 ES512 PS256 PS384 PS512]
      @allow_hmac = false
      @leeway = 30
    end

    def to_h
      {
        algorithm: algorithm,
        issuer: issuer,
        audience: audience,
        jwks_uri: jwks_uri,
        jwks_ttl: jwks_ttl,
        token_lifetime: token_lifetime,
        allowed_algorithms: allowed_algorithms,
        allow_hmac: allow_hmac,
        leeway: leeway
      }
    end
  end
end
