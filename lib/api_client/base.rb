# frozen_string_literal: true

require 'active_support/configurable'
require 'faraday'
require 'faraday_middleware'
require 'faraday/encoding'

# ORM-ish for data-transfer between services
module ApiClient
  # persistent-ish connection to a generic service
  # rubocop:disable Metrics/ClassLength
  class Base
    include ActiveSupport::Configurable

    config_accessor :faraday_adapter        # => :net_http (default)
    config_accessor :timeout_in_seconds     # => 3
    config_accessor :service_uri            # => 'http://localhost:8080'
    config_accessor :base_path              # => '/'
    config_accessor :default_headers        # => {}
    config_accessor :default_parameters     # => {}
    config_accessor :middlewares            # => []
    config_accessor :log_requests           # => false
    config_accessor :log_request_bodies     # => false
    config_accessor :logger                 # => STDOUT
    config_accessor :retry_options          # => {}
    config_accessor :expected_response_type # => :json

    # default adapter is net_http i.e. ::Faraday.default_adapter
    #
    # see: https://github.com/lostisland/awesome-faraday/#adapters
    #
    # adapter               | considerations
    # ----------------------+-------------------------------------------
    # :httpclient           | +compression,-streaming,+socket,-parallel
    # :net_http             | +compression,+streaming,-socket,-parallel
    # :net_http_persistent  | +compression,-streaming,-socket,-parallel
    # :em_http              | -compression,-streaming,+socket,+parallel
    config.faraday_adapter = ::Faraday.default_adapter

    # log requests
    config.log_requests = ActiveRecord::Type::Boolean.new.cast(
      ENV.fetch('FARADAY_LOG_REQUESTS', true)
    )
    config.log_request_bodies = ActiveRecord::Type::Boolean.new.cast(
      ENV.fetch('FARADAY_LOG_REQUEST_BODIES', true)
    )
    config.logger = STDOUT

    # default HTTP timeout,, in seconds
    config.timeout_in_seconds = 3

    # https://lostisland.github.io/faraday/middleware/retry
    config.retry_options = {
      max: 2, interval: 0.05, interval_randomness: 0.5, backoff_factor: 2
    }

    # client specific defaults
    config.service_uri = 'http://localhost:8080'
    config.base_path = '/'
    config.default_headers = {
      'Accept' => 'application/json', 'Content-Type' => 'application/json'
    }
    config.default_parameters = {}

    # parse responses as JSON by default
    config.expected_response_type = :json

    # https://github.com/lostisland/awesome-faraday/#middleware
    # https://lostisland.github.io/faraday/middleware/instrumentation
    config.default_middlewares = Set.new(
      %i[
        instrumentation
      ].concat(
        [
          # FaradayMiddleware::Gzip,
          # FaradayMiddleware::ParseJson,
          FaradayMiddleware::Chunked,
          FaradayMiddleware::ParseDates
        ]
      )
    )

    # request specific attributes
    attr_accessor :http_headers, :parameters, :middlewares, :expected_response_type

    # convenience function
    def config
      self.class.config
    end

    # rubocop:disable Metrics/AbcSize
    def initialize(**kwargs)
      config.service_uri = kwargs.fetch(:service_uri, config.service_uri)
      config.base_path = kwargs.fetch(:base_path, config.base_path)
      config.timeout_in_seconds = kwargs.fetch(:timeout_in_seconds, config.timeout_in_seconds)

      @http_headers = kwargs.fetch(:http_headers, {}).reverse_merge(config.default_headers)
      @parameters = kwargs.fetch(:parameters, {}).reverse_merge(config.default_parameters)
      @middlewares = kwargs.fetch(:middlewares, Set.new).merge(config.default_middlewares)
      @expected_response_type = kwargs.fetch(:response_type, config.expected_response_type)
    end
    # rubocop:enable Metrics/AbcSize

    def connection
      @connection ||= new_connection(uri: api_version_uri)
    end

    delegate :post, :get, :put, :patch, :delete, to: :connection

    # trace external requests to track request-queue times for external services
    if respond_to?(:add_method_tracer)
      %i[post get put patch delete].each do |meth|
        add_method_tracer meth, "#{self.class}/connection/#{meth}"
      end
    end

    def api_version_uri
      @api_version_uri ||= URI.join(config.service_uri, config.base_path)
    end

    # rubocop:disable Metrics/AbcSize
    def new_connection(uri:)
      ::Faraday.new(url: uri) do |faraday|
        faraday.request :url_encoded
        # faraday.request :multipart
        faraday.request :json
        faraday.request :retry, config.retry_coptions

        faraday.options[:timeout] = config.timeout

        faraday.headers.merge!(http_headers)

        faraday.params.merge!(parameters)

        middlewares.each { |ware| faraday.use ware }

        # good if every response from this connection is JSON,
        # else it throws errors... not gracefully
        # faraday.response :json if expected_response_type == :json

        faraday.response :encoding

        # NOTE: do not augment from to end of block. There be dragons
        log_response(faraday: faraday)

        # NOTE: must be called after middlewares
        faraday.adapter config.faraday_adapter
      end
    end
    # rubocop:enable Metrics/AbcSize

    # request HTML response as JSON
    def expect_html_response
      http_headers.merge!('Accept' => 'text/html')
      self.expected_response_type = :html
    end

    # request JSON response as JSON
    def expect_json_response
      http_headers.merge!('Accept' => 'application/json')
      self.expected_response_type = :json
    end

    def handle_response(response:)
      if success_response?(response: response)
        response.body
      else
        handle_error(response: response)
        response
      end
    end

    def success_response?(response:)
      status = response.status
      status >= 200 && status < 400
    end

    # NOTE: inherit this and super
    # TODO: consolidate logger stdout/stderr vs Rails.logger
    def handle_error(response:)
      Rails.logger.error do
        {
          request_uri: "#{api_version_uri}?#{parameters.to_param}",
          response_status: response.status,
          response_headers: response.headers,
          response_body: response.body
        }
      end
    end

    REDACT_AUTH_FROM_LOGS = /(authorization\s*:\s*)(?:"|')?(?:.*?)(?:'|")?.*/i.freeze

    def log_response(faraday:)
      return unless config.log_requests

      faraday.response :logger, api_logger, bodies: config.log_request_bodies do |logger|
        logger.filter(REDACT_AUTH_FROM_LOGS, '\1[REDACTED]')
      end
    end

    # TODO: consolidate logger stdout/stderr vs Rails.logger
    # TODO: newrelic, splunk
    def api_logger
      @api_logger ||= (defined?(::Rails) ? ::Rails.logger : Logger.new($stdout))
    end
  end
  # rubocop:enable Metrics/ClassLength
end
