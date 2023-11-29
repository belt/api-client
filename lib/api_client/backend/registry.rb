require_relative "../concerns/registry_base"

module ApiClient
  module Backend
    # Registry for HTTP backends with auto-detection and plugin support
    #
    # Manages core backends and user-registered plugins. Detection order
    # prioritizes best-of-breed backends for I/O-bound HTTP operations:
    #
    # 1. Typhoeus - HTTP/2, pipelining, Hydra concurrency
    # 2. Async - Fiber-based, Ruby 3+ optimized
    # 3. Concurrent - Thread pool based
    # 4. Sequential - Fallback (always available)
    #
    # @example Register custom backend
    #   Backend::Registry.register(:my_backend, MyBackendClass)
    #
    # @example Auto-detect best backend
    #   backend_sym = Backend::Registry.detect
    #   backend_class = Backend::Registry.resolve(backend_sym)
    #
    module Registry
      extend Concerns::RegistryBase

      CORE_BACKENDS = %i[typhoeus async concurrent sequential].freeze

      self.registry_items = CORE_BACKENDS.dup
      self.fallback_item = :sequential
      self.item_label = "backend"

      @register_mutex = Mutex.new

      # Class instance variables below are intentional: mutex-guarded registry state for thread-safe backend resolution.
      class << self
        # Register a custom backend
        #
        # @param name [Symbol] Backend identifier
        # @param klass [Class] Backend class implementing Interface
        # @raise [ArgumentError] if name conflicts or class invalid
        #
        def register(name, klass)
          name = name.to_sym

          if CORE_BACKENDS.include?(name)
            raise ArgumentError, I18n.t("backend.cannot_override_core", name: name)
          end

          unless klass.method_defined?(:execute)
            raise ArgumentError, I18n.t("backend.must_implement_execute", klass: klass)
          end

          unless klass.method_defined?(:config)
            raise ArgumentError, I18n.t("backend.must_implement_config", klass: klass)
          end

          @register_mutex.synchronize do
            @custom_backends ||= {}
            @custom_backends[name] = klass

            # Add to registry items for detection
            @registry_items = (CORE_BACKENDS + @custom_backends.keys).freeze
            # Clear memoized caches from RegistryBase
            @available_items = nil
            @availability = nil
            @detected = nil
          end
        end

        # Get backend class for given name
        #
        # @param backend [Symbol] Backend identifier
        # @return [Class] Backend class
        # @raise [NoAdapterError] if backend not found
        #
        def resolve(backend)
          backend = backend.to_sym

          # Check custom backends first
          if @custom_backends&.key?(backend) # standard:disable ThreadSafety/ClassInstanceVariable
            return @custom_backends[backend] # standard:disable ThreadSafety/ClassInstanceVariable
          end

          # Fall back to core backends
          case backend
          when :typhoeus then require_typhoeus
          when :async then require_async
          when :concurrent then require_concurrent
          when :sequential then require_sequential
          else raise NoAdapterError, I18n.t("backend.unknown", backend: backend)
          end
        end

        # Reverse lookup: class → name
        #
        # @param klass [Class] Backend class
        # @return [Symbol, nil] Backend name or nil if not found
        #
        def backend_name(klass)
          # Check custom backends
          if @custom_backends # standard:disable ThreadSafety/ClassInstanceVariable
            name = @custom_backends.key(klass) # standard:disable ThreadSafety/ClassInstanceVariable
            return name if name
          end

          # Check core backends
          CORE_BACKENDS.find { |name| resolve(name) == klass }
        rescue NoAdapterError
          nil
        end

        private

        def check_availability(backend)
          backend = backend.to_sym

          # Custom backends are always "available" if registered
          return true if @custom_backends&.key?(backend) # standard:disable ThreadSafety/ClassInstanceVariable

          # Core backend availability checks
          # Attempt require so availability is independent of load order
          case backend
          when :typhoeus then gem_loadable?("typhoeus")
          when :async then RUBY_VERSION >= "3.0" && gem_loadable?("async", "async/http/internet")
          when :concurrent then gem_loadable?("concurrent")
          when :sequential then true
          else false
          end
        end

        def gem_loadable?(*gems)
          gems.each { |g| require g }
          true
        rescue LoadError
          false
        end

        def require_typhoeus
          require_relative "../adapters/typhoeus_adapter"
          Adapters::TyphoeusAdapter
        end

        def require_async
          require_relative "../adapters/async_adapter"
          Adapters::AsyncAdapter
        end

        def require_concurrent
          require_relative "../adapters/concurrent_adapter"
          Adapters::ConcurrentAdapter
        end

        def require_sequential
          require_relative "../orchestrators/sequential"
          Orchestrators::Sequential
        end
      end
    end
  end
end
