module ApiClient
  # Backend management for HTTP adapters
  #
  # Provides a registry pattern for HTTP backends with auto-detection,
  # graceful fallback, and plugin support. Backends handle I/O-bound
  # HTTP request execution with different concurrency models.
  #
  # Core backends (auto-detected in priority order):
  # 1. Typhoeus - HTTP/2, pipelining, Hydra concurrency
  # 2. Async - Fiber-based, Ruby 3+ optimized
  # 3. Concurrent - Thread pool based
  # 4. Sequential - Fallback (always available)
  #
  # @example Register custom backend
  #   class MyBackend
  #     include ApiClient::Backend::Interface
  #     def execute(requests); ...; end
  #   end
  #   ApiClient::Backend.register(:my_backend, MyBackend)
  #
  # @example Auto-detect best backend
  #   backend_name = ApiClient::Backend.detect
  #   backend_class = ApiClient::Backend.resolve(backend_name)
  #
  module Backend
    class << self
      # Register a custom backend
      # @param name [Symbol] Backend identifier
      # @param klass [Class] Backend class implementing Interface
      # @raise [ArgumentError] if name already registered or class invalid
      def register(name, klass)
        Registry.register(name, klass)
      end

      # Auto-detect best available backend
      # @return [Symbol] Backend name
      def detect
        Registry.detect
      end

      # Resolve backend name to class
      # @param name [Symbol] Backend identifier
      # @return [Class] Backend class
      # @raise [NoAdapterError] if backend not found
      def resolve(name)
        Registry.resolve(name)
      end

      # Check if backend is available
      # @param name [Symbol] Backend identifier
      # @return [Boolean]
      def available?(name)
        Registry.available?(name)
      end

      # List all available backends
      # @return [Array<Symbol>]
      def available
        Registry.available_items
      end

      # Reverse lookup: class → name
      # @param klass [Class] Backend class
      # @return [Symbol, nil]
      def backend_name(klass)
        Registry.backend_name(klass)
      end
    end
  end
end

require_relative "backend/interface"
require_relative "backend/registry"
