require "etc"
require "json"
require "digest"
require "openssl"
require_relative "base_processor"
require_relative "error_strategy"
require_relative "ractor_pool"
require_relative "../request_flow/registry"

module ApiClient
  module Processing
    # Parallel processor for CPU-bound response transformations
    #
    # Uses Ractor pool for true parallel execution of CPU-intensive work
    # like JSON parsing, checksums, and HMAC verification.
    #
    # @example Basic usage
    #   processor = RactorProcessor.new
    #   parsed = processor.map(responses)
    #
    # @example With parameter objects
    #   processor.map(responses,
    #     recipe: Transforms::Recipe.default,
    #     errors: ErrorStrategy.skip)
    #
    class RactorProcessor
      include BaseProcessor
      include ProcessorInstrumentation

      # Delegate to shared Transforms module
      TRANSFORMS = Transforms.available.freeze

      attr_reader :pool, :min_batch_size, :min_payload_size, :default_error_strategy

      # @param pool [:global, :instance, RactorPool] Pool strategy
      # @param pool_size [Integer] Size for new pools (ignored if pool provided)
      # @param min_batch_size [Integer] Skip Ractor for smaller batches
      # @param min_payload_size [Integer] Skip Ractor for smaller payloads (bytes)
      # @param errors [ErrorStrategy] Default error strategy
      def initialize(
        pool: :global,
        pool_size: nil,
        min_batch_size: nil,
        min_payload_size: nil,
        errors: nil
      )
        proc_config = config.processor_config
        @pool = resolve_pool(pool, pool_size)
        @min_batch_size = min_batch_size || proc_config.ractor_min_batch_size
        @min_payload_size = min_payload_size || proc_config.ractor_min_payload_size
        @default_error_strategy = errors || ErrorStrategy.default
      end

      # Shutdown the pool (only affects instance pools)
      def shutdown
        @pool.shutdown if @owns_pool
      end

      private

      def resolve_pool(pool_option, pool_size)
        case pool_option
        when :global
          @owns_pool = false
          self.class.global_pool
        when :instance
          @owns_pool = true
          RactorPool.new(size: pool_size || config.processor_config.ractor_pool_size)
        when RactorPool
          @owns_pool = false
          pool_option
        else
          raise ArgumentError, I18n.t("processing.invalid_pool_option", option: pool_option.inspect)
        end
      end

      def use_sequential?(items, extract)
        return true if items.size < min_batch_size

        # Check payload size on first item
        extractor = resolve_extractor(extract)
        sample = extractor.call(items.first)
        sample_size = sample.respond_to?(:bytesize) ? sample.bytesize : 0

        sample_size < min_payload_size
      end

      def parallel_map(items, recipe:, errors:, &block)
        extractor = resolve_extractor(recipe.extract)

        raw_results, raw_errors = pool.process(items, extractor:, transform: recipe.transform)

        # Index error positions for O(1) lookup
        error_indices = raw_errors.each_with_object({}) { |err, idx| idx[err[:index]] = err }

        results = []
        error_list = []

        # Handle pool-level errors first (fail_fast raises immediately)
        raw_errors.each do |err|
          err_index = err[:index]
          error = build_error(err)
          handle_error(
            index: err_index, item: items[err_index],
            error:, errors:, results: [], error_list:
          )
        end

        # Build results array, applying user block where successful
        raw_results.each_with_index do |result, index|
          if error_indices.key?(index)
            errors.apply(build_error(error_indices[index]), results)
            next
          end

          begin
            final = block ? block.call(result) : result
            results << final
          rescue => error
            handle_error(index:, item: items[index], error:, errors:, results:, error_list:)
          end
        end

        errors.finalize(results, error_list, processing_error_class)
      end

      # ProcessorInstrumentation implementation
      def instrument_event_prefix
        :ractor
      end

      def instrument_start_metadata
        {pool_size: pool.size}
      end

      # BaseProcessor implementation
      def processing_error_class
        RactorProcessingError
      end

      class << self
        # standard:disable ThreadSafety/ClassInstanceVariable
        @global_pool = nil
        @global_pool_mutex = Mutex.new
        @owns_pool = nil

        def global_pool
          @global_pool_mutex ||= Mutex.new
          @global_pool_mutex.synchronize do
            @global_pool ||= RactorPool.new(
              size: ApiClient.configuration.processor_config.ractor_pool_size
            )
          end
        end

        def reset_global_pool!
          @global_pool_mutex&.synchronize do
            @global_pool&.shutdown
            @global_pool = nil
          end
        end
        # standard:enable ThreadSafety/ClassInstanceVariable
      end
    end

    # Register with RequestFlow::Registry for dynamic dispatch
    RequestFlow::Registry.register_processor(:parallel_map) { RactorProcessor }
  end
end
