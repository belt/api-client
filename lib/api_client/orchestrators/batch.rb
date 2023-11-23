module ApiClient
  module Orchestrators
    # Batch HTTP request orchestrator with auto-detected backend
    #
    # Dispatches multiple HTTP requests using the best available backend:
    # Typhoeus > Async > Concurrent > Sequential
    #
    # For CPU-bound parallel data processing, see Processing::Registry.
    #
    # @example
    #   batch = Batch.new(config)
    #   responses = batch.execute([
    #     { method: :get, path: '/users/1' },
    #     { method: :get, path: '/users/2' }
    #   ])
    #
    class Batch
      attr_reader :config, :backend

      # @param config [Configuration] ApiClient configuration
      # @param adapter [Symbol, nil] Backend name (optional, auto-detected)
      def initialize(config = ApiClient.configuration, adapter: nil)
        @config = config
        @backend = resolve_backend(adapter)
      end

      # Execute requests (concurrently when backend supports it)
      # @param requests [Array<Hash>] Array of request hashes
      # @return [Array<Faraday::Response>]
      def execute(requests)
        return [] if requests.empty?

        backend.execute(requests)
      end

      # Current backend name
      # @return [Symbol]
      def backend_name
        Backend.backend_name(backend.class) || :unknown
      end

      # Alias for backward compatibility
      alias_method :adapter, :backend
      alias_method :adapter_name, :backend_name

      private

      def resolve_backend(forced_backend)
        backend_sym = forced_backend || Backend.detect
        backend_class = Backend.resolve(backend_sym)
        backend_class.new(config)
      end
    end
  end
end
