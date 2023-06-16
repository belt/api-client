require "connection_pool"

module ApiClient
  module Concerns
    # Shared connection pooling behavior
    #
    # Provides a thread-safe ConnectionPool wrapper around a factory block.
    # When pooling is disabled, falls back to a single instance with a
    # `.with`-compatible interface (no gem dependency for the fallback path).
    #
    # @example Including in a class
    #   class MyConnection
    #     include Concerns::Poolable
    #
    #     def initialize(config)
    #       @config = config
    #       @pool = build_pool(config.pool_config) { create_connection }
    #     end
    #
    #     def request(...)
    #       with_pooled_connection { |conn| conn.run_request(...) }
    #     end
    #   end
    #
    module Poolable
      private

      # Build a ConnectionPool or NullPool from config
      # @param pool_config [PoolConfig] Pool configuration
      # @yield Factory block that creates a new connection
      # @return [ConnectionPool, NullPool]
      def build_pool(pool_config, &factory)
        if pool_config.enabled
          ConnectionPool.new(size: pool_config.size, timeout: pool_config.timeout, &factory)
        else
          NullPool.new(&factory)
        end
      end

      # Execute block with a pooled connection (checkout/checkin)
      # @yield [connection] Checked-out connection
      # @return [Object] Block result
      def with_pooled_connection(&block)
        @pool.with(&block)
      end

      # Pool metrics for observability
      # @return [Hash] :size, :available, :type
      def pool_stats
        {
          size: @pool.size,
          available: @pool.available,
          type: @pool.is_a?(ConnectionPool) ? :connection_pool : :null_pool
        }
      end
    end

    # Pass-through pool when pooling is disabled
    #
    # Holds a single instance and yields it directly.
    # Same `.with` interface as ConnectionPool for transparent swap.
    #
    class NullPool
      def initialize(&factory)
        @instance = factory.call
      end

      # Yield the single instance (no checkout/checkin)
      # @yield [connection]
      # @return [Object] Block result
      def with
        yield @instance
      end

      # @return [Integer] Always 1
      def size
        1
      end

      # @return [Integer] Always 1
      def available
        1
      end

      # No-op shutdown
      def shutdown
        # nothing to do
      end

      # No-op reload
      def reload
        # nothing to do
      end

      # Yield the single instance (ConnectionPool compatibility)
      # @yield [connection]
      # @return [Object] Block result
      def then
        yield @instance
      end
    end
  end
end
