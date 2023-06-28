module ApiClient
  # Lightweight probe that detects Faraday-style builder blocks and captures
  # their intent so it can be applied to an ApiClient::Configuration.
  #
  # When a user writes:
  #
  #   ApiClient.new(url: '...') do |f|
  #     f.request :json
  #     f.response :logger
  #     f.adapter :net_http
  #     f.options.timeout = 10
  #   end
  #
  # The FaradayBuilder captures those calls and translates them into
  # Configuration settings. Unrecognized calls are silently ignored so
  # the probe doesn't raise when yielded to an ApiClient-style block
  # that sets config attributes directly.
  class FaradayBuilder
    attr_reader :adapter_name, :options_proxy

    def initialize
      @faraday_calls = false
      @adapter_name = nil
      @options_proxy = OptionsProxy.new
      @logger_config = nil
      @config_calls = []
    end

    # Faraday-style: f.request :json, f.request :retry, opts
    def request(middleware, *_args)
      @faraday_calls = true
      # Middleware is handled internally by Connection — nothing to capture
      # except :retry which maps to retry_config
      nil
    end

    # Faraday-style: f.response :logger, f.response :json
    def response(middleware, *args, **kwargs, &block)
      @faraday_calls = true
      if middleware == :logger
        @logger_config = {logger: args.first, bodies: kwargs[:bodies]}
      end
      nil
    end

    # Faraday-style: f.adapter :net_http
    def adapter(name = nil, *_args)
      @faraday_calls = true
      @adapter_name = name if name
      nil
    end

    # Faraday-style: f.options.timeout = 10
    def options
      @faraday_calls = true
      @options_proxy
    end

    # Faraday-style: f.headers = {...} or f.headers.update(...)
    def headers
      @faraday_calls = true
      @headers_hash ||= {}
    end

    def headers=(hash)
      @faraday_calls = true
      @headers_hash = hash
    end

    # Faraday-style: f.params = {...}
    def params
      @faraday_calls = true
      @params_hash ||= {}
    end

    def params=(hash)
      @faraday_calls = true
      @params_hash = hash
    end

    # Did the block make any Faraday-style calls?
    def faraday_style?
      @faraday_calls
    end

    # Apply captured Faraday-style settings to an ApiClient::Configuration
    def apply_to(config)
      config.adapter = @adapter_name if @adapter_name
      apply_timeouts(config)
      apply_headers(config)
      apply_params(config)
      apply_logger(config)
    end

    # Record unknown method calls (Configuration-style attribute setters)
    # so they can be replayed on the real Configuration without calling
    # the block a second time.
    def method_missing(method, *args, &block)
      # Don't flag as faraday_style — unknown calls are assumed to be
      # Configuration-style attribute setters
      @config_calls << [method, args, block]
      nil
    end

    def respond_to_missing?(_method, _include_private = false)
      true
    end

    # Replay captured Configuration-style calls onto a real Configuration.
    # Warns for any call that doesn't match a Configuration method, which
    # catches typos like `config.raed_timeout = 30` early.
    # @param config [Configuration] Target configuration
    def apply_config_calls(config)
      @config_calls.each do |method, args, block|
        if config.respond_to?(method)
          config.public_send(method, *args, &block)
        else
          config.logger&.warn do
            "ApiClient::FaradayBuilder: unknown configuration method '#{method}' " \
            "(not a method on ApiClient::Configuration). Possible typo?"
          end
        end
      end
    end

    private

    def apply_timeouts(config)
      config.open_timeout = @options_proxy.open_timeout if @options_proxy.open_timeout
      config.read_timeout = @options_proxy.read_timeout if @options_proxy.read_timeout
      config.write_timeout = @options_proxy.write_timeout if @options_proxy.write_timeout
      # Faraday's `timeout` sets read_timeout
      config.read_timeout = @options_proxy.timeout if @options_proxy.timeout
    end

    def apply_headers(config)
      config.default_headers = config.default_headers.merge(@headers_hash) if @headers_hash&.any?
    end

    def apply_params(config)
      config.default_params = config.default_params.merge(@params_hash) if @params_hash&.any?
    end

    def apply_logger(config)
      return unless @logger_config

      config.log_requests = true
      config.logger = @logger_config[:logger] if @logger_config[:logger]
      config.log_bodies = @logger_config[:bodies] if @logger_config[:bodies]
    end

    # Captures Faraday-style f.options.timeout = 10, f.options.open_timeout = 5, etc.
    class OptionsProxy
      attr_accessor :timeout, :open_timeout, :read_timeout, :write_timeout

      def initialize
        @timeout = nil
        @open_timeout = nil
        @read_timeout = nil
        @write_timeout = nil
      end
    end
  end
end
