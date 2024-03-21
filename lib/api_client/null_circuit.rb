module ApiClient
  # Shared interface for circuit breaker implementations.
  #
  # Both {Circuit} (Stoplight-backed) and {NullCircuit} (pass-through)
  # include this module, making duck-typing explicit and enabling
  # +is_a?(CircuitInterface)+ checks.
  #
  module CircuitInterface
    # Execute block within circuit breaker
    # @yield Block to execute
    # @return [Object] Block result or fallback value
    def run
      raise NotImplementedError
    end

    # Set fallback value when circuit is open
    # @return [self]
    def with_fallback
      raise NotImplementedError
    end

    # Set custom error handler
    # @return [self]
    def on_error
      raise NotImplementedError
    end

    # @return [Boolean] true if circuit is open (failing fast)
    def open?
      raise NotImplementedError
    end

    # @return [Boolean] true if circuit is closed (healthy)
    def closed?
      raise NotImplementedError
    end

    # @return [Boolean] true if circuit is half-open (probing)
    def half_open?
      raise NotImplementedError
    end

    # @return [String] Current state
    def state
      raise NotImplementedError
    end

    # @return [Integer] Number of recorded failures
    def failure_count
      raise NotImplementedError
    end

    # @return [Array<Hash>] Recent failures
    def recent_failures(limit: 10)
      raise NotImplementedError
    end

    # @return [Hash] Health metrics
    def metrics
      raise NotImplementedError
    end

    # Reset circuit to closed state
    def reset!
      raise NotImplementedError
    end
  end

  # Null-object stand-in for {Circuit} when Stoplight is not installed.
  #
  # Implements the same public interface as {Circuit} so callers never
  # need conditional checks, but also performs no failure tracking, state
  # transitions, or fail-fast behaviour:
  #
  # - +run+ always yields the block directly
  # - +with_fallback+ / +on_error+ are silent no-ops (return +self+)
  # - +open?+ is always +false+; +state+ is always +"green"+
  # - +failure_count+ is always +0+; +recent_failures+ is always +[]+
  # - +metrics+ includes +enabled: false+ to signal the circuit is inert
  #
  # This means every request reaches the network regardless of downstream
  # health — there is no threshold, no cool-off, and no automatic
  # recovery probing. Fallback blocks are silently discarded.
  #
  # @example
  #   circuit = NullCircuit.new('service')
  #   circuit.run { expensive_call }  # Always executes block
  #   circuit.open?                   # Always false
  #
  # @see Circuit Full implementation backed by Stoplight
  #
  class NullCircuit
    include CircuitInterface

    attr_reader :name, :config

    # @param name [String] Circuit identifier (for interface compatibility)
    # @param config [CircuitConfig, nil] Ignored, kept for interface compatibility
    def initialize(name, config = nil)
      @name = name
      @config = config
    end

    # Execute block directly (no circuit breaker)
    # @yield Block to execute
    # @return [Object] Block result
    def run
      yield
    end

    # Set fallback (no-op — NullCircuit never opens, so fallbacks are never invoked)
    #
    # Logs at debug level to help catch misconfiguration where code expects
    # fallback behavior but Stoplight is not loaded.
    # @return [self]
    def with_fallback(&block)
      if block
        ApiClient.configuration.logger&.debug do
          "NullCircuit(#{name}): fallback block registered but will never execute " \
          "(Stoplight not loaded or circuit disabled)"
        end
      end
      self
    end

    # Set error handler (no-op, returns self for chaining)
    # @return [self]
    def on_error
      self
    end

    # Always closed (healthy)
    # @return [Boolean] Always false
    def open?
      false
    end

    # Always closed
    # @return [Boolean] Always true
    def closed?
      true
    end

    # Never half-open
    # @return [Boolean] Always false
    def half_open?
      false
    end

    # Always green
    # @return [String] Always "green"
    def state
      "green"
    end

    # No failures tracked
    # @return [Integer] Always 0
    def failure_count
      0
    end

    # No failures to report
    # @param limit [Integer] Ignored
    # @return [Array] Always empty
    def recent_failures(limit: 10)
      []
    end

    # Metrics showing disabled state
    # @return [Hash]
    def metrics
      {
        name: name,
        state: "green",
        failure_count: 0,
        threshold: nil,
        cool_off: nil,
        window_size: nil,
        enabled: false
      }
    end

    # No-op reset
    def reset!
      # Nothing to reset
    end
  end
end
