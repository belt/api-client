module ApiClient
  class RequestFlow
    # Shared step configuration for parallel processing steps
    #
    # Reduces duplication in parallel_map, async_map, concurrent_map, and process steps.
    #
    module StepHelpers
      # Build step options hash for parallel processing steps
      #
      # @param recipe [Transforms::Recipe] Extraction and transformation recipe
      # @param errors [ErrorStrategy, nil] Error handling strategy
      # @param block [Proc] Optional post-transform block
      # @return [Hash] Step options
      def self.build_processor_step_options(recipe:, errors:, block:)
        {recipe: recipe, errors: errors, block: block}
      end

      # Execute a processor step with the given type and options
      #
      # @param type [Symbol] Processor type (:parallel_map, :async_map, :concurrent_map)
      # @param opts [Hash] Step options
      # @param items [Array] Items to process
      # @param registry [Module] Registry module for processor lookup
      # @return [Array] Processed results
      def self.execute_processor(type, opts, items, registry)
        processor_class = registry.processor(type)
        execute_with_processor(processor_class, opts, items)
      end

      # Execute a processor with the given class and options
      #
      # @param processor_class [Class] Processor class to instantiate
      # @param opts [Hash] Step options
      # @param items [Array] Items to process
      # @return [Array] Processed results
      def self.execute_with_processor(processor_class, opts, items)
        processor = processor_class.new
        processor.map(
          Array(items),
          recipe: opts[:recipe],
          errors: opts[:errors],
          &opts[:block]
        )
      end
    end
  end
end
