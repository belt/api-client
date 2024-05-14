module ApiClient
  module Processing
    # Encapsulates processing state for parallel operations
    #
    # Addresses DataClump smell by grouping commonly passed parameters:
    # - results array (pre-allocated or growing)
    # - error_list for collecting failures
    # - error strategy for handling failures
    #
    # @example Creating context for indexed results (parallel)
    #   context = ProcessingContext.indexed(size: 10, errors: ErrorStrategy.skip)
    #   context.store_result(0, "value")
    #   context.record_error(1, item, error)
    #
    # @example Creating context for sequential results
    #   context = ProcessingContext.sequential(errors: ErrorStrategy.fail_fast)
    #   context.append_result("value")
    #
    ProcessingContext = Data.define(:results, :error_list, :errors, :indexed) do
      class << self
        # Create context for indexed/parallel processing with pre-allocated array
        # @param size [Integer] Number of items to process
        # @param errors [ErrorStrategy] Error handling strategy
        # @return [ProcessingContext]
        def indexed(size:, errors:)
          new(
            results: Array.new(size),
            error_list: [],
            errors: errors,
            indexed: true
          )
        end

        # Create context for sequential processing with growing array
        # @param errors [ErrorStrategy] Error handling strategy
        # @return [ProcessingContext]
        def sequential(errors:)
          new(
            results: [],
            error_list: [],
            errors: errors,
            indexed: false
          )
        end
      end

      # Store result at specific index (for parallel processing)
      # @param index [Integer] Position in results array
      # @param value [Object] Result value
      def store_result(index, value)
        results[index] = value
      end

      # Append result to array (for sequential processing)
      # @param value [Object] Result value
      def append_result(value)
        results << value
      end

      # Record an error that occurred during processing
      # @param index [Integer] Item index where error occurred
      # @param item [Object] Original item that failed
      # @param error [Exception] The error that occurred
      # @return [Hash] Error info hash
      def record_error(index, item, error)
        error_info = {index: index, item: item, error: error}
        error_list << error_info
        error_info
      end

      # Check if any errors occurred
      # @return [Boolean]
      def errors?
        !error_list.empty?
      end

      # Get error handling strategy symbol
      # @return [Symbol]
      def strategy
        errors.strategy
      end

      # Get fallback value for :replace strategy
      # @return [Object, nil]
      def fallback
        errors.fallback
      end

      # Check if strategy will raise on completion
      # @return [Boolean]
      def raises_on_error?
        errors.raises?
      end

      # Get count of errors
      # @return [Integer]
      def error_count
        error_list.size
      end

      # Get count of successful results
      # @return [Integer]
      def success_count
        results.count { |r| !r.nil? && !r.equal?(Processing::SKIPPED) }
      end

      # Finalize and return results based on strategy
      # @param error_class [Class] Error class to raise for :collect strategy
      # @return [Array] Final results
      # @raise [ProcessingError] if strategy is :collect and errors present
      def finalize(error_class:)
        # Pre-allocated indexed arrays have nil slots for unprocessed items;
        # strip them before delegating to ErrorStrategy#finalize.
        compacted = results.reject(&:nil?)
        errors.finalize(compacted, error_list, error_class)
      end
    end
  end
end
