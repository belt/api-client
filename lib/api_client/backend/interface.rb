module ApiClient
  module Backend
    # Interface contract for HTTP backends
    #
    # All backends must implement this interface to be compatible with
    # the registry system. Backends handle I/O-bound HTTP request
    # execution with different concurrency models.
    #
    # @example Implementing a custom backend
    #   class MyBackend
    #     include ApiClient::Backend::Interface
    #
    #     def initialize(config = ApiClient.configuration)
    #       @config = config
    #     end
    #
    #     def execute(requests)
    #       requests.map { |req| make_http_call(req) }
    #     end
    #   end
    #
    module Interface
      # Execute HTTP requests
      #
      # @param requests [Array<Hash>] Request specifications
      #   Each hash must contain:
      #   - :method [Symbol] HTTP method (:get, :post, etc.)
      #   - :path [String] Request path
      #   - :headers [Hash, nil] Request headers
      #   - :params [Hash, nil] Query parameters
      #   - :body [Object, nil] Request body
      #
      # @return [Array<Faraday::Response>] Responses in same order as requests
      #
      # @raise [StandardError] Backend-specific errors
      #
      def execute(requests)
        raise NotImplementedError, I18n.t("interface.must_implement", klass: self.class, method_name: "execute")
      end

      # Configuration accessor
      #
      # @return [Configuration] ApiClient configuration
      #
      def config
        raise NotImplementedError, I18n.t("interface.must_implement", klass: self.class, method_name: "config")
      end
    end
  end
end
