require_relative "../hooks"
require_relative "../http_verbs"
require_relative "../adapters/instrumentation"

module ApiClient
  # Orchestrators for HTTP request dispatch
  #
  # Provides sequential and concurrent request orchestration
  # with automatic adapter detection.
  #
  module Orchestrators
    # Execute a single request hash via connection
    # @param connection [Connection] ApiClient connection
    # @param req [Hash] Request hash with :method, :path, :params, :headers, :body
    # @return [Faraday::Response]
    def self.execute_request(connection, req)
      connection.request(
        req[:method],
        req[:path],
        params: req.fetch(:params, HttpVerbs::EMPTY_HASH),
        headers: req.fetch(:headers, HttpVerbs::EMPTY_HASH),
        body: req[:body]
      )
    end

    # Sequential HTTP request orchestrator
    #
    # Dispatches requests one at a time using the connection.
    # Returns array of Faraday::Response objects.
    #
    # @example With config (used by Concurrent)
    #   sequential = Sequential.new(config)
    #   responses = sequential.execute([...])
    #
    # @example With connection (direct use)
    #   sequential = Sequential.new(connection)
    #   responses = sequential.execute([...])
    #
    class Sequential
      include Adapters::Instrumentation

      attr_reader :connection

      # @param config_or_connection [Configuration, Connection] Config or connection
      def initialize(config_or_connection)
        @connection = resolve_connection(config_or_connection)
      end

      # Execute requests sequentially
      # @param requests [Array<Hash>] Array of request hashes
      # @return [Array<Faraday::Response>]
      def execute(requests)
        return [] if requests.empty?

        with_batch_instrumentation(:sequential, requests) do
          requests.map { |req| Orchestrators.execute_request(connection, req) }
        end
      end

      # Delegate config to connection for instrumentation
      def config
        connection.config
      end

      private

      def resolve_connection(config_or_connection)
        if config_or_connection.is_a?(Connection)
          config_or_connection
        else
          Connection.new(config_or_connection)
        end
      end
    end
  end
end
