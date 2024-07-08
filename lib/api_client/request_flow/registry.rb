require "nxt_registry"

module ApiClient
  class RequestFlow
    # Registry for request flow step processors and adapters
    #
    # Processors and adapters self-register at require time, enabling
    # lazy loading and extensibility without modifying RequestFlow.
    #
    # @example Processor registration (in processor file)
    #   RequestFlow::Registry.register_processor(:parallel_map) { RactorProcessor }
    #
    # @example Adapter registration (in adapter file)
    #   RequestFlow::Registry.register_adapter(:typhoeus) { TyphoeusAdapter }
    #
    # @example RequestFlow dispatch
    #   if Registry.processor?(:parallel_map)
    #     klass = Registry.processor(:parallel_map)
    #     klass.new.map(items, **opts)
    #   end
    #
    module Registry
      extend NxtRegistry

      # Registry for CPU-bound processors (*_map steps)
      # Keys: :parallel_map, :async_map, :concurrent_map
      # Values: Proc returning processor class (lazy-loaded)
      registry :processors do
        call false
        memoize true
      end

      # Registry for HTTP adapters (fan_out dispatch)
      # Keys: :typhoeus, :async, :concurrent, :sequential
      # Values: Proc returning adapter class (lazy-loaded)
      registry :adapters do
        call false
        memoize true
      end

      class << self
        # Register a processor with lazy loading
        # @param key [Symbol] Processor key (e.g., :parallel_map)
        # @yield Returns processor class
        def register_processor(key, &block)
          registry(:processors).register(key, block)
        end

        # Register an adapter with lazy loading
        # @param key [Symbol] Adapter key (e.g., :typhoeus)
        # @yield Returns adapter class
        def register_adapter(key, &block)
          registry(:adapters).register(key, block)
        end

        # Check if a processor is registered
        # @param key [Symbol] Processor key (e.g., :parallel_map)
        # @return [Boolean]
        def processor?(key)
          registered?(:processors, key)
        end

        # Get processor class (lazy-loaded)
        # @param key [Symbol] Processor key
        # @return [Class] Processor class
        # @raise [KeyError] if processor not registered
        def processor(key)
          resolve_entry(:processors, key)
        end

        # Check if an adapter is registered
        # @param key [Symbol] Adapter key (e.g., :typhoeus)
        # @return [Boolean]
        def adapter?(key)
          registered?(:adapters, key)
        end

        # Get adapter class (lazy-loaded)
        # @param key [Symbol] Adapter key
        # @return [Class] Adapter class
        # @raise [KeyError] if adapter not registered
        def adapter(key)
          resolve_entry(:adapters, key)
        end

        # List registered processor keys
        # @return [Array<Symbol>]
        def processor_keys
          registry(:processors).keys.map(&:to_sym)
        end

        # List registered adapter keys
        # @return [Array<Symbol>]
        def adapter_keys
          registry(:adapters).keys.map(&:to_sym)
        end

        private

        def registered?(registry_name, key)
          !registry(registry_name).resolve(key).nil?
        end

        def resolve_entry(registry_name, key)
          proc = registry(registry_name).resolve(key)
          raise KeyError, I18n.t("registry.unknown_entry", entry_type: registry_name.to_s.chomp("s"), key: key) if proc.nil?

          proc.call
        end
      end
    end
  end
end
