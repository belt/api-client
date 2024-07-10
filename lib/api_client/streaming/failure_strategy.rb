module ApiClient
  module Streaming
    # Defines behavior when a fan-out request fails at the transport level.
    #
    # Mirrors Processing::ErrorStrategy's shape but handles fan-out
    # specifics: indexed vs arrival-order storage, Proc callbacks with
    # (source, request) arity, and deferred raise via finalize.
    #
    # Strategies:
    # - :fail_fast - Raise immediately on first failure
    # - :collect   - Store failed value, raise FanOutError at finalize
    # - :skip      - Silently drop the failure
    # - Proc       - Call proc(source, request) for a fallback value
    #
    # @example Fail fast (default)
    #   FailureStrategy.fail_fast
    #
    # @example Skip failures
    #   FailureStrategy.skip
    #
    # @example Custom fallback
    #   FailureStrategy.callback(->(source, req) { default_response })
    #
    FailureStrategy = Data.define(:strategy, :handler) do
      class << self
        # Raise immediately on first failure (default)
        # @return [FailureStrategy]
        def fail_fast
          new(strategy: :fail_fast, handler: nil)
        end

        # Collect failures, raise FanOutError at finalize
        # @return [FailureStrategy]
        def collect
          new(strategy: :collect, handler: nil)
        end

        # Skip failed items silently
        # @return [FailureStrategy]
        def skip
          new(strategy: :skip, handler: nil)
        end

        # Use a Proc to produce a fallback value
        # @param proc [Proc] Called with (source, request)
        # @return [FailureStrategy]
        def callback(proc)
          new(strategy: :callback, handler: proc)
        end

        # Default strategy
        # @return [FailureStrategy]
        def default
          fail_fast
        end

        # Build from the raw on_fail option value
        # @param on_fail [Symbol, Proc] :fail_fast, :skip, :collect, or a Proc
        # @return [FailureStrategy]
        def from(on_fail)
          case on_fail
          when :fail_fast then fail_fast
          when :skip then skip
          when :collect then collect
          when Proc then callback(on_fail)
          else fail_fast
          end
        end
      end

      # Apply the strategy to a single failure.
      #
      # @param index [Integer] Request index
      # @param source [Object] Original failure (response or exception)
      # @param request [Hash] Original request
      # @param results [Array] Results array to store into
      # @param errors [Array] Errors array to append failure info to
      # @param failure [Hash] Serialized failure info
      # @param raise_error [Exception] Error to raise for :fail_fast
      # @param preserve_order [Boolean] true for indexed storage, false for append
      # @yield [response, index] Streaming callback
      def apply(
        index:, source:, request:, results:, errors:,
        failure:, raise_error:, preserve_order:, &block
      )
        errors << failure

        case strategy
        when :fail_fast
          raise raise_error
        when :skip
          nil
        when :collect
          store(source, index, results, preserve_order, &block)
        when :callback
          fallback = handler.call(source, request)
          store(fallback, index, results, preserve_order, &block) unless fallback.nil?
        end
      end

      # Finalize results after all requests complete.
      # Raises FanOutError for :collect when errors are present.
      # Clears :raw references from errors to prevent memory anchoring.
      #
      # @param results [Array] Collected results
      # @param errors [Array] Collected error hashes
      # @param preserve_order [Boolean] Whether results use indexed storage
      # @return [Array] Final results
      def finalize(results, errors, preserve_order)
        errors.each { |e| e.delete(:raw) }

        if strategy == :collect && errors.any?
          raise ApiClient::FanOutError.new(results.compact, errors)
        end

        preserve_order ? results : results.compact
      end

      private

      def store(value, index, results, preserve_order, &block)
        if preserve_order
          results[index] = value
        else
          results << value
        end

        block&.call(value, index)
      end
    end
  end
end
