require "etc"
require_relative "base_processor"
require_relative "error_strategy"
require_relative "../request_flow/registry"

begin
  require "concurrent"
rescue LoadError
  # concurrent-ruby is optional; ConcurrentProcessor unavailable without it
end

module ApiClient
  module Processing
    # Parallel processor using concurrent-ruby thread pool
    #
    # Alternative to RactorProcessor and AsyncProcessor for CPU-bound work.
    # Uses thread pool via Concurrent::Future for parallel execution.
    #
    # Trade-offs:
    # - GVL limits true CPU parallelism (but still useful for mixed I/O+CPU)
    # - Lower overhead than fork-based AsyncProcessor
    # - More portable than Ractor (works on JRuby, TruffleRuby)
    # - Shared memory (no serialization overhead)
    #
    # Best for:
    # - Mixed I/O and CPU workloads
    # - JRuby/TruffleRuby (true parallelism due to no GVL)
    # - Lower latency requirements (no fork/IPC overhead)
    #
    # @example Basic usage
    #   processor = ConcurrentProcessor.new
    #   parsed = processor.map(responses)
    #
    # @example With parameter objects
    #   processor.map(responses,
    #     recipe: Transforms::Recipe.default,
    #     errors: ErrorStrategy.skip)
    #
    class ConcurrentProcessor
      include BaseProcessor
      include ProcessorInstrumentation

      attr_reader :pool_size, :min_batch_size, :default_error_strategy

      # @param pool_size [Integer] Number of threads in pool
      # @param min_batch_size [Integer] Skip threading for smaller batches
      # @param errors [ErrorStrategy] Default error strategy
      def initialize(
        pool_size: nil,
        min_batch_size: nil,
        errors: nil
      )
        require_concurrent!
        @pool_size = pool_size || config.processor_config.concurrent_processor_pool_size
        @min_batch_size = min_batch_size ||
          config.processor_config.concurrent_processor_min_batch_size
        @default_error_strategy = errors || ErrorStrategy.default
      end

      # Check if concurrent-ruby is available
      def self.available?
        defined?(::Concurrent) ? true : false
      end

      private

      def require_concurrent!
        return if defined?(::Concurrent)

        raise LoadError,
          I18n.t("processing.concurrent_ruby_required")
      end

      def use_sequential?(items, _extract = nil)
        items.size < min_batch_size
      end

      def parallel_map(items, recipe:, errors:, &block)
        extractor = resolve_extractor(recipe.extract)
        error_list = Concurrent::Array.new

        # Create futures for parallel execution
        futures = items.each_with_index.map do |item, index|
          Concurrent::Future.execute(executor: thread_pool) do
            data = extractor.call(item)
            transformed = Transforms.apply(recipe.transform, data)
            result = block ? block.call(transformed) : transformed
            [index, :ok, result]
          rescue => error
            error_list << {index:, item:, error:}
            [index, :error, error]
          end
        end

        # Collect results maintaining order
        raw_results = futures.map { |f| f.value(config.read_timeout) }
        results = Array.new(items.size)

        raw_results.each do |index, status, payload|
          if status == :ok
            results[index] = payload
          else
            errors.apply_indexed(index, payload, results)
          end
        end

        # Instrument errors
        error_list.each { |err| instrument_error(err, errors.strategy) }

        errors.finalize(results, error_list.to_a, processing_error_class)
      end

      def thread_pool
        @thread_pool ||= Concurrent::FixedThreadPool.new(pool_size)
      end

      # ProcessorInstrumentation implementation
      def instrument_event_prefix
        :concurrent_processor
      end

      def instrument_start_metadata
        {pool_size:}
      end

      # BaseProcessor implementation
      def processing_error_class
        ConcurrentProcessingError
      end
    end

    # Register with RequestFlow::Registry for dynamic dispatch
    RequestFlow::Registry.register_processor(:concurrent_map) { ConcurrentProcessor }
  end
end
