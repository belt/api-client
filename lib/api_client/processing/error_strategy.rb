module ApiClient
  module Processing
    # Defines behavior when transformation fails
    #
    # Encapsulates the error handling strategy and fallback value
    # for processor operations (map, select, reduce).
    #
    # Strategies:
    # - :fail_fast - Raise immediately on first error
    # - :collect   - Collect all errors, raise at end with partial results
    # - :skip      - Skip failed items, continue processing
    # - :replace   - Replace failed items with fallback value
    #
    # @example Fail fast (default)
    #   ErrorStrategy.fail_fast
    #
    # @example Skip failures
    #   ErrorStrategy.skip
    #
    # @example Replace with default value
    #   ErrorStrategy.replace({})
    #
    # Sentinel value for slots where an error was handled by :skip or :collect.
    # Distinguishes "transform returned nil" from "this slot had an error".
    SKIPPED = Object.new.freeze

    ErrorStrategy = Data.define(:strategy, :fallback) do
      class << self
        # Fail immediately on first error (default)
        # @return [ErrorStrategy]
        def fail_fast
          new(strategy: :fail_fast, fallback: nil)
        end

        # Collect all errors, raise at end with partial results
        # @return [ErrorStrategy]
        def collect
          new(strategy: :collect, fallback: nil)
        end

        # Skip failed items, continue processing
        # @return [ErrorStrategy]
        def skip
          new(strategy: :skip, fallback: nil)
        end

        # Replace failed items with fallback value
        # @param value [Object] Fallback value to use
        # @return [ErrorStrategy]
        def replace(value)
          new(strategy: :replace, fallback: value)
        end

        # Default strategy (fail_fast)
        # @return [ErrorStrategy]
        def default
          fail_fast
        end
      end

      # Check if strategy will raise on error
      # @return [Boolean]
      def raises?
        strategy == :fail_fast || strategy == :collect
      end

      # Apply error strategy to a results array (append-based)
      # @param error [Exception] The error that occurred
      # @param results [Array] Results array to modify
      # @return [void]
      def apply(error, results)
        case strategy
        when :fail_fast then raise error
        when :collect then results << SKIPPED
        when :skip then nil # Don't add to results
        when :replace then results << fallback
        end
      end

      # Apply error strategy to a pre-allocated indexed results array
      # @param index [Integer] Item index
      # @param error [Exception] The error that occurred
      # @param results [Array] Pre-allocated results array
      # @return [void]
      def apply_indexed(index, error, results)
        case strategy
        when :fail_fast then raise error
        when :collect then results[index] = SKIPPED
        when :skip then results[index] = SKIPPED
        when :replace then results[index] = fallback
        end
      end

      # Finalize results based on strategy and collected errors
      # @param results [Array] Collected results
      # @param errors [Array] Collected error info hashes
      # @param error_class [Class] Error class for :collect strategy
      # @return [Array] Final results
      def finalize(results, errors, error_class)
        cleaned = results.reject { |r| r.equal?(SKIPPED) }
        return cleaned if errors.empty?

        case strategy
        when :collect then raise error_class.new(cleaned, errors)
        when :replace then results.reject { |r| r.equal?(SKIPPED) }
        else cleaned
        end
      end
    end
  end
end
