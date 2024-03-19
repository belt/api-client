begin
  require "stoplight"
rescue LoadError
  # Stoplight is optional; circuit breaker disabled without it
end

require_relative "null_circuit"

module ApiClient
  # Circuit breaker wrapper around Stoplight (optional dependency).
  #
  # Prevents cascading failures by tracking errors against a downstream
  # service and short-circuiting requests once a failure threshold is
  # reached. The pattern has three states:
  #
  #   closed  (green)  — requests flow normally, failures are counted
  #   open    (red)    — requests are rejected immediately (fail-fast)
  #   half-open (yellow) — one probe request is allowed through after
  #                        the cool-off period to test recovery
  #
  # When Stoplight is not installed, +Circuit.new+ returns a {NullCircuit}
  # instead — a transparent pass-through that preserves the same public
  # interface but performs no failure tracking, state transitions, or
  # fail-fast behaviour.
  #
  # @example Basic usage
  #   circuit = Circuit.new('payment-api', config.circuit_config)
  #   circuit.run { connection.get('/health') }
  #
  # @example With fallback
  #   circuit = Circuit.new('payment-api', config.circuit_config)
  #   circuit.with_fallback { cached_response }.run { connection.get('/health') }
  #
  # @example With custom error handler
  #   circuit = Circuit.new('payment-api', config.circuit_config)
  #   circuit.on_error { |error| notify_ops(error) }.run { risky_call }
  #
  # @see NullCircuit Pass-through used when Stoplight is absent
  # @see CircuitConfig Configuration options (threshold, cool_off, window_size)
  #
  class Circuit
    include CircuitInterface

    # Factory method that returns NullCircuit when Stoplight unavailable
    # @param name [String] Circuit identifier
    # @param config [CircuitConfig] Circuit configuration
    # @return [Circuit, NullCircuit]
    def self.new(name, config = ApiClient.configuration.circuit_config)
      return NullCircuit.new(name, config) unless defined?(::Stoplight)
      return NullCircuit.new(name, config) unless config.enabled

      instance = allocate
      instance.send(:initialize, name, config)
      instance
    end

    @error_notifier_mutex = Mutex.new
    @error_notifier_configured = false

    attr_reader :name, :config

    # @param name [String] Circuit identifier (typically service name)
    # @param config [CircuitConfig] Circuit configuration
    def initialize(name, config = ApiClient.configuration.circuit_config)
      @name = name
      @config = config
      @light = nil
      @state_mutex = Mutex.new
      @fallback_block = nil
      @error_handler = nil
      @failure_count = 0
      @recent_failures = []
      @max_recent_failures = 100
    end

    # Set fallback value when circuit is open
    # @yield Block returning fallback value
    # @return [self] For chaining
    def with_fallback(&block)
      @fallback_block = block
      self
    end

    # Set custom error handler for this circuit
    # @yield [error] Block called on errors
    # @return [self] For chaining
    def on_error(&block)
      @error_handler = block
      self
    end

    # Execute block within circuit breaker
    # @yield Block to execute
    # @return [Object] Block result or fallback value
    # @raise [CircuitOpenError] When circuit is open and no fallback set
    def run(&block)
      light.run(&block)
    rescue Stoplight::Error::RedLight => error
      handle_open_circuit(error)
    rescue => error
      record_failure(error)
      @error_handler&.call(error)
      raise
    end

    # Check if circuit is open (failing fast)
    # @return [Boolean]
    def open?
      light.color == Stoplight::Color::RED
    end

    # Check if circuit is closed (healthy)
    # @return [Boolean]
    def closed?
      !open?
    end

    # Check if circuit is half-open (probing)
    # @return [Boolean]
    def half_open?
      light.color == Stoplight::Color::YELLOW
    end

    # Current circuit state
    # @return [String] 'green', 'yellow', or 'red'
    def state
      light.color
    end

    # Get failure count (tracked locally)
    # @return [Integer]
    def failure_count
      @state_mutex.synchronize { @failure_count }
    end

    # Get recent failures with timestamps
    # @param limit [Integer] Max failures to return
    # @return [Array<Hash>] Recent failures
    def recent_failures(limit: 10)
      @state_mutex.synchronize do
        @recent_failures.last(limit)
      end
    end

    # Circuit health metrics
    # @return [Hash] Health metrics
    def metrics
      {
        name: name,
        state: state,
        failure_count: failure_count,
        threshold: config.threshold,
        cool_off: config.cool_off,
        window_size: config.window_size
      }
    end

    # Reset circuit to closed state
    #
    # @note When using a Redis data store, this writes a GREEN lock to the
    #   shared store. Calling reset! on one node affects all nodes sharing
    #   the same Stoplight data store.
    def reset!
      @state_mutex.synchronize do
        # Lock to green to clear state in Stoplight's data store
        @light&.lock(Stoplight::Color::GREEN)
        @light = nil
        @fallback_block = nil
        @error_handler = nil
        @failure_count = 0
        @recent_failures = []
      end
    end

    class << self
      attr_reader :error_notifier_configured

      def configure_global_error_notifier
        @error_notifier_mutex.synchronize do
          return if @error_notifier_configured

          Stoplight.configure do |stoplight_config|
            stoplight_config.error_notifier = lambda { |error|
              Hooks.instrument(:circuit_error, error: error)
            }
          end
          @error_notifier_configured = true
        end
      end

      # Reset global configuration (for testing)
      def reset_global_config!
        @error_notifier_mutex.synchronize do
          @error_notifier_configured = false
        end
      end
    end

    private

    def record_failure(error)
      @state_mutex.synchronize do
        @failure_count += 1
        @recent_failures << {
          error: error.class.name,
          message: error.message,
          time: Time.now
        }
        # Keep bounded
        @recent_failures.shift if @recent_failures.size > @max_recent_failures
      end
    end

    def handle_open_circuit(error)
      Hooks.instrument(:circuit_rejected, service: name, error: error)

      if @fallback_block
        Hooks.instrument(:circuit_fallback, service: name)
        @fallback_block.call
      else
        raise CircuitOpenError.new(name)
      end
    end

    def light
      # Double-checked locking: avoid mutex on every call after first build.
      # @light is only written once (nil → Stoplight instance) and the
      # Stoplight object is thread-safe, so reading without the mutex
      # after initialization is safe.
      return @light if @light

      @state_mutex.synchronize do
        @light ||= build_light
      end
    end

    def build_light
      self.class.configure_global_error_notifier

      window = config.window_size
      tracked = config.tracked_errors

      options = {
        threshold: config.threshold,
        cool_off_time: config.cool_off,
        notifiers: [StateNotifier.new(name)]
      }

      # Add window_size if configured
      options[:window_size] = window if window

      # Add tracked_errors if configured
      options[:tracked_errors] = tracked if tracked&.any?

      # Use Redis data store when configured (pool or raw client)
      data_store = resolve_data_store
      options[:data_store] = data_store if data_store

      Stoplight(name, **options)
    end

    # Resolve the Stoplight data store from config
    # Prefers redis_pool (ConnectionPool) over raw redis_client
    # @return [Stoplight::DataStore::Redis, nil]
    def resolve_data_store
      return nil unless config.data_store == :redis

      pool_or_client = config.redis_pool || config.redis_client
      return nil unless pool_or_client

      if defined?(::Stoplight::DataStore::Redis)
        ::Stoplight::DataStore::Redis.new(pool_or_client)
      end
    end
  end

  # Stoplight notifier that instruments circuit state transitions.
  #
  # Emits +:circuit_open+, +:circuit_half_open+, and +:circuit_close+
  # events through {Hooks} whenever the circuit changes colour.
  #
  class StateNotifier < Stoplight::Notifier::Base
    attr_reader :service_name

    def initialize(service_name)
      @service_name = service_name
    end

    def notify(light, from_color, to_color, error)
      event = case to_color
      when Stoplight::Color::RED then :circuit_open
      when Stoplight::Color::YELLOW then :circuit_half_open
      else :circuit_close
      end

      Hooks.instrument(event,
        service: service_name,
        from: from_color,
        to: to_color,
        error: error)
    end
  end
end
