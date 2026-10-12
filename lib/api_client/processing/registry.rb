require_relative "../concerns/registry_base"
require_relative "../transforms"
require_relative "base_processor"
require_relative "error_strategy"

module ApiClient
  module Processing
    # Registry for processors with auto-detection and graceful fallback
    #
    # Provides unified processor discovery, availability checking, and
    # class resolution. Experimental Ractor processing is explicit-only.
    # Default detection order:
    # 1. Async - Fork-based parallelism via async-container
    # 2. Concurrent - Thread pool (true parallelism on JRuby/TruffleRuby)
    # 3. Sequential fallback
    # Ractor is available only through explicit selection.
    #
    # @example Auto-detect best processor
    #   processor_sym = Processing::Registry.detect
    #   processor_class = Processing::Registry.resolve(processor_sym)
    #   processor = processor_class.new
    #
    module Registry
      extend Concerns::RegistryBase

      PROCESSORS = %i[async concurrent sequential ractor].freeze

      self.registry_items = PROCESSORS
      self.fallback_item = :sequential
      self.item_label = "processor"

      # standard:disable ThreadSafety/ClassInstanceVariable
      class << self
        # Alias for backward compatibility
        alias_method :available_processors, :available_items

        # Get processor class for given name
        # @param processor [Symbol]
        # @return [Class]
        def resolve(processor)
          case processor
          when :ractor then require_ractor
          when :async then require_async
          when :concurrent then require_concurrent
          when :sequential then SequentialProcessor
          else raise ArgumentError, I18n.t("processing.unknown_processor", processor: processor)
          end
        end

        # Reverse lookup: class → name
        # @param klass [Class]
        # @return [Symbol, nil]
        def processor_name(klass)
          PROCESSORS.find { |name| resolve(name) == klass }
        rescue ArgumentError
          nil
        end

        private

        def check_availability(processor)
          case processor
          when :ractor then !defined?(Ractor::Port).nil?
          when :async then !defined?(::Async::Container).nil?
          when :concurrent then !defined?(::Concurrent).nil?
          when :sequential then true
          else false
          end
        end

        def require_ractor
          require_relative "ractor_processor"
          RactorProcessor
        end

        def require_async
          require_relative "async_processor"
          AsyncProcessor
        end

        def require_concurrent
          require_relative "concurrent_processor"
          ConcurrentProcessor
        end
      end
      # standard:enable ThreadSafety/ClassInstanceVariable
    end

    # Minimal sequential processor fallback
    class SequentialProcessor
      include BaseProcessor
      include ProcessorInstrumentation

      attr_reader :default_error_strategy

      def initialize
        @default_error_strategy = ErrorStrategy.skip
      end

      def self.available?
        true
      end

      # BaseProcessor implementation
      def processing_error_class
        ProcessingError
      end

      private

      def use_sequential?(_items, _extract = nil)
        true
      end

      def parallel_map(items, recipe:, errors:, &block)
        sequential_map(items, recipe:, errors:, &block)
      end

      def instrument_event_prefix
        :sequential_processor
      end
    end
  end
end
