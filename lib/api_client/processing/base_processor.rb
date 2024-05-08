require_relative "../transforms"
require_relative "../error"
require_relative "../hooks"
require_relative "error_strategy"

module ApiClient
  module Processing
    # Shared extractors for response data
    #
    # Used by all processor implementations to extract data from responses.
    #
    EXTRACTORS = {
      body: ->(response) { response.respond_to?(:body) ? response.body : response },
      status: ->(response) {
        response.respond_to?(:status) ? response.status : response
      },
      headers: ->(response) {
        response.respond_to?(:headers) ? response.headers.to_h : response
      },
      identity: ->(response) { response }
    }.freeze

    # Base processor module with shared logic for all processor implementations
    #
    # Provides common functionality:
    # - Extractor resolution
    # - Sequential map implementation
    # - Error handling
    # - Result finalization
    #
    # @example Including in a processor
    #   class MyProcessor
    #     include BaseProcessor
    #
    #     def initialize
    #       @default_error_strategy = ErrorStrategy.skip
    #     end
    #
    #     # Must implement: parallel_map, use_sequential?, processing_error_class
    #   end
    #
    module BaseProcessor
      # Resolve extractor from symbol or proc
      # @param extract [Symbol, Proc] Extractor specification
      # @return [Proc] Extractor lambda
      # @raise [ArgumentError] if extractor invalid
      def resolve_extractor(extract)
        case extract
        when Symbol
          EXTRACTORS.fetch(extract) { raise ArgumentError, I18n.t("extractors.unknown", extract: extract) }
        when Proc
          extract
        else
          raise ArgumentError, I18n.t("extractors.invalid_type")
        end
      end

      # Map over items with parallel or sequential dispatch
      #
      # @param items [Array] Items to process
      # @param recipe [Transforms::Recipe] Extraction and transformation recipe
      # @param errors [ErrorStrategy] Error handling strategy (defaults to processor's default)
      # @yield [item] Block to transform extracted data
      # @return [Array] Transformed results
      def map(items, recipe: Transforms::Recipe.default, errors: nil, &block)
        errors ||= default_error_strategy
        items_array = Array(items)
        count = items_array.size

        return [] if count.zero?

        instrument_start(:map, count)

        results = if use_sequential?(items_array, recipe.extract)
          sequential_map(items_array, recipe:, errors:, &block)
        else
          parallel_map(items_array, recipe:, errors:, &block)
        end

        instrument_complete(:map, count, results.size)
        results
      end

      # Sequential map implementation (shared across all processors)
      # @param items [Array] Items to process
      # @param recipe [Transforms::Recipe] Extraction and transformation recipe
      # @param errors [ErrorStrategy] Error handling strategy
      # @yield [transformed] Block to apply after transform
      # @return [Array] Results
      def sequential_map(items, recipe:, errors:, &block)
        extractor = resolve_extractor(recipe.extract)
        results = []
        error_list = []

        items.each_with_index do |item, index|
          data = extractor.call(item)
          transformed = Transforms.apply(recipe.transform, data)
          result = block ? block.call(transformed) : transformed
          results << result
        rescue => error
          handle_error(index:, item:, error:, errors:, results:, error_list:)
        end

        errors.finalize(results, error_list, processing_error_class)
      end

      # Parallel map implementation (must be implemented by subclass)
      # @param items [Array] Items to process
      # @param recipe [Transforms::Recipe] Extraction and transformation recipe
      # @param errors [ErrorStrategy] Error handling strategy
      # @yield [transformed] Block to apply after transform
      # @return [Array] Results
      def parallel_map(items, recipe:, errors:, &block)
        raise NotImplementedError, I18n.t("interface.must_implement", klass: self.class, method_name: "parallel_map")
      end

      # Determine if sequential processing should be used
      # @param items [Array] Items to process
      # @param extract [Symbol, Proc] Extractor specification
      # @return [Boolean] true if sequential should be used
      def use_sequential?(items, extract)
        raise NotImplementedError, I18n.t("interface.must_implement", klass: self.class, method_name: "use_sequential?")
      end

      # Handle processing error according to strategy
      # @param index [Integer] Item index
      # @param item [Object] Original item
      # @param error [Exception] Error that occurred
      # @param errors [ErrorStrategy] Error handling strategy
      # @param results [Array] Results array to modify
      # @param error_list [Array] Errors array to append to
      def handle_error(index:, item:, error:, errors:, results:, error_list:)
        record_and_instrument_error(index:, item:, error:, error_list:, strategy: errors.strategy)
        errors.apply(error, results)
      end

      # Handle error for indexed results (parallel processing with pre-allocated array)
      # @param index [Integer] Item index
      # @param item [Object] Original item
      # @param error [Exception] Error that occurred
      # @param errors [ErrorStrategy] Error handling strategy
      # @param results [Array] Pre-allocated results array to modify by index
      # @param error_list [Array] Errors array to append to
      def handle_indexed_error(index:, item:, error:, errors:, results:, error_list:)
        record_and_instrument_error(index:, item:, error:, error_list:, strategy: errors.strategy)
        errors.apply_indexed(index, error, results)
      end

      # Handle error result for indexed results (when error already collected)
      # @param index [Integer] Item index
      # @param error [Exception] Error that occurred
      # @param errors [ErrorStrategy] Error handling strategy
      # @param results [Array] Pre-allocated results array to modify by index
      def handle_indexed_error_result(index:, error:, errors:, results:)
        errors.apply_indexed(index, error, results)
      end

      # Finalize results based on error strategy
      # @param results [Array] Collected results
      # @param error_list [Array] Collected errors
      # @param errors [ErrorStrategy] Error handling strategy
      # @return [Array] Final results
      # @raise [ProcessingError] if strategy is :collect and errors present
      def finalize_results(results:, error_list:, errors:)
        errors.finalize(results, error_list, processing_error_class)
      end

      # Finalize indexed results (alias for finalize_results - same logic)
      alias_method :finalize_indexed_results, :finalize_results

      # Build error from serialized error hash (for IPC scenarios)
      # @param error_hash [Hash] Serialized error with :error_class and :message
      # @return [Exception] Reconstructed error
      def build_error(error_hash)
        klass = begin
          Object.const_get(error_hash[:error_class])
        rescue
          StandardError
        end
        klass.new(error_hash[:message])
      end

      # Get ApiClient configuration
      # @return [Configuration]
      def config
        ApiClient.configuration
      end

      # Parallel select/filter (shared implementation)
      #
      # Delegates to #map for parallel transformation, then filters.
      # Subclasses only need to implement #map.
      #
      # @param items [Array] Items to filter
      # @param recipe [Transforms::Recipe] Extraction and transformation recipe
      # @param errors [ErrorStrategy] Error handling strategy
      # @yield [transformed_item] Predicate block
      # @return [Array] Items where predicate returned truthy
      def select(items, recipe: Transforms::Recipe.default, errors: nil, &predicate)
        errors ||= default_error_strategy
        items_array = Array(items)
        count = items_array.size

        return [] if count.zero?

        instrument_start(:select, count)
        transformed = map(items_array, recipe:, errors:)
        results = items_array.zip(transformed)
          .select { |_item, trans| predicate.call(trans) }
          .map(&:first)
        instrument_complete(:select, count, results.size)
        results
      end

      # Parallel reduce (shared implementation)
      #
      # Delegates to #map for parallel transformation, then reduces sequentially.
      # Subclasses only need to implement #map.
      #
      # @param items [Array] Items to reduce
      # @param initial [Object] Initial accumulator value
      # @param recipe [Transforms::Recipe] Extraction and transformation recipe
      # @param errors [ErrorStrategy] Error handling strategy
      # @yield [accumulator, transformed_item] Reducer block
      # @return [Object] Final accumulated value
      def reduce(items, initial, recipe: Transforms::Recipe.default, errors: nil, &reducer)
        errors ||= default_error_strategy
        items_array = Array(items)

        return initial if items_array.empty?

        instrument_start(:reduce, items_array.size)
        result = map(items_array, recipe:, errors:).reduce(initial, &reducer)
        instrument_complete(:reduce, items_array.size, 1)
        result
      end

      # Must be implemented by including class
      # @return [Class] Error class to raise for :collect strategy
      def processing_error_class
        raise NotImplementedError, I18n.t("interface.must_implement", klass: self.class, method_name: "processing_error_class")
      end

      # Must be implemented by including class for instrumentation
      def instrument_error(error_info, strategy)
        raise NotImplementedError, I18n.t("interface.must_implement", klass: self.class, method_name: "instrument_error")
      end

      private

      # Record error info and instrument it (shared by handle_error and handle_indexed_error)
      def record_and_instrument_error(index:, item:, error:, error_list:, strategy:)
        error_info = {index:, item:, error:}
        error_list << error_info
        instrument_error(error_info, strategy)
      end
    end

    # Instrumentation concern for processors
    #
    # Provides standardized instrumentation hooks for processor operations.
    # Each processor specifies its event prefix (e.g., :ractor, :async).
    #
    # @example Including in a processor
    #   class MyProcessor
    #     include ProcessorInstrumentation
    #
    #     def instrument_event_prefix
    #       :my_processor
    #     end
    #   end
    #
    module ProcessorInstrumentation
      # Instrument operation start
      # @param operation [Symbol] Operation name (:map, :select, :reduce)
      # @param count [Integer] Number of items
      def instrument_start(operation, count)
        Hooks.instrument(
          event_symbols[:start],
          operation:,
          count:,
          **instrument_start_metadata
        )
      end

      # Instrument operation completion
      # @param operation [Symbol] Operation name
      # @param input_count [Integer] Input item count
      # @param output_count [Integer] Output item count
      def instrument_complete(operation, input_count, output_count)
        Hooks.instrument(
          event_symbols[:complete],
          operation:,
          input_count:,
          output_count:
        )
      end

      # Instrument processing error
      # @param error_info [Hash] Error details with :index, :error keys
      # @param strategy [Symbol] Error handling strategy
      def instrument_error(error_info, strategy)
        Hooks.instrument(
          event_symbols[:error],
          index: error_info[:index],
          error: error_info[:error],
          strategy:,
          will_raise: strategy == :fail_fast || strategy == :collect
        )
      end

      # Event prefix for instrumentation (must be implemented)
      # @return [Symbol] Event prefix (e.g., :ractor, :async_processor)
      def instrument_event_prefix
        raise NotImplementedError, I18n.t("interface.must_implement", klass: self.class, method_name: "instrument_event_prefix")
      end

      # Additional metadata for start events (override in subclass)
      # @return [Hash] Additional metadata
      def instrument_start_metadata
        {}
      end

      private

      # Pre-computed event symbols per prefix. Avoids string interpolation
      # + to_sym on every instrument call (hot path for processors).
      # Memoized per instance since instrument_event_prefix is fixed.
      def event_symbols
        @event_symbols ||= {
          start: :"#{instrument_event_prefix}_start",
          complete: :"#{instrument_event_prefix}_complete",
          error: :"#{instrument_event_prefix}_error"
        }.freeze
      end
    end
  end
end
