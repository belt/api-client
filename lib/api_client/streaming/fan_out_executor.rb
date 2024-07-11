require "async"
require "async/barrier"
require "etc"
require_relative "../hooks"
require_relative "../error"
require_relative "failure_strategy"

module ApiClient
  module Streaming
    # Streaming fan-out executor with backpressure and per-request retry
    #
    # Executes requests concurrently, streaming results to the next stage
    # as they complete rather than waiting for all to finish.
    #
    # @example Basic streaming
    #   executor = FanOutExecutor.new(config, adapter)
    #   executor.execute(requests) do |response, index|
    #     process(response)
    #   end
    #
    class FanOutExecutor
      # Default max concurrent requests: nproc * √2
      DEFAULT_MAX_INFLIGHT = (Etc.nprocessors * Math.sqrt(2)).round

      # Default retry configuration
      DEFAULT_RETRY = {backoff: :exponential}.freeze

      # Default backoff cap in seconds
      DEFAULT_MAX_BACKOFF = 30

      # Ceiling for timeout_ms to prevent effectively-infinite timeouts.
      # Configurable via Configuration#fan_out_max_timeout_ms.
      # Default: 10 minutes — generous enough for slow upstreams, bounded
      # enough to catch accidental misconfiguration.
      DEFAULT_MAX_TIMEOUT_MS = 600_000

      # Exceptions eligible for retry — constant since async is required
      # at file load time.
      RETRYABLE_EXCEPTIONS = [
        Async::TimeoutError,
        Errno::ECONNREFUSED,
        SocketError,
        IOError
      ].freeze

      attr_reader :config, :adapter, :options, :failure_strategy

      # @param config [Configuration] ApiClient configuration
      # @param adapter [Object] HTTP adapter instance
      # @param options [Hash] Fan-out options
      # @option options [Symbol, Proc] :on_ready (:stream) :stream, :batch, or Proc
      # @option options [Symbol, Proc] :on_fail (:fail_fast) :skip, :fail_fast, :collect, or Proc
      # @option options [Symbol] :order (:preserve) :preserve or :arrival
      # @option options [Integer] :max_inflight Concurrent request limit
      # @option options [Integer] :timeout_ms Per-request timeout in milliseconds (max: 600_000)
      # @option options [Hash, false] :retries Retry configuration
      # @option options [Numeric] :max_backoff Maximum backoff delay in seconds (default: 30)
      def initialize(config, adapter, **options)
        @config = config
        @adapter = adapter
        @options = normalize_options(options)
        @failure_strategy = FailureStrategy.from(options.fetch(:on_fail, :fail_fast))
        @prng = Random.new
      end

      # Execute fan-out requests
      # @param requests [Array<Hash>] Request specifications
      # @yield [response, index] Called for each completed response (streaming mode)
      # @return [Array<Faraday::Response>] All responses (ordered per :order option)
      # @raise [ArgumentError] If requests is not an Array of Hash-like objects
      def execute(requests, &on_ready_block)
        validate_requests!(requests)
        return [] if requests.empty?

        count = requests.size
        instrument_start(count)
        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        results = case effective_on_ready
        when :batch
          execute_batch(requests)
        when :stream
          execute_streaming(requests, &on_ready_block)
        when Proc
          execute_streaming(requests, &effective_on_ready)
        end

        duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
        instrument_complete(count, results.size, duration)

        results
      end

      private

      def validate_requests!(requests)
        unless requests.is_a?(Array)
          raise ArgumentError,
            I18n.t("fan_out.invalid_requests_type", klass: requests.class)
        end

        return if requests.empty?

        first = requests.first
        unless first.respond_to?(:fetch)
          raise ArgumentError,
            I18n.t("fan_out.invalid_request_item", klass: first.class)
        end
      end

      def normalize_options(opts)
        timeout_ms = opts[:timeout_ms]
        max_timeout = config.fan_out_max_timeout_ms || DEFAULT_MAX_TIMEOUT_MS
        if timeout_ms
          validate_timeout_ms!(timeout_ms)
          timeout_ms = [timeout_ms, max_timeout].min
        end

        on_ready = opts.fetch(:on_ready, :stream)
        order = opts.fetch(:order, :preserve)
        max_inflight = opts.fetch(:max_inflight, DEFAULT_MAX_INFLIGHT)
        retries = normalize_retry(opts.fetch(:retries, DEFAULT_RETRY))
        max_backoff = opts.fetch(:max_backoff, DEFAULT_MAX_BACKOFF)

        {
          on_ready: on_ready,
          order: order,
          max_inflight: max_inflight,
          timeout_ms: timeout_ms,
          retries: retries,
          max_backoff: max_backoff
        }
      end

      def validate_timeout_ms!(timeout_ms)
        unless timeout_ms.is_a?(Numeric) && timeout_ms.positive?
          raise ArgumentError, I18n.t("fan_out.invalid_timeout", value: timeout_ms.inspect)
        end
      end

      def normalize_retry(retry_opt)
        case retry_opt
        when false, nil then nil
        when Hash then DEFAULT_RETRY.merge(retry_opt)
        else DEFAULT_RETRY
        end
      end

      def effective_on_ready
        options[:on_ready]
      end

      def request_timeout_seconds
        timeout_ms = options[:timeout_ms]
        if timeout_ms
          timeout_ms / 1000.0
        else
          config.read_timeout
        end
      end

      def execute_batch(requests)
        adapter.execute(requests)
      end

      def execute_streaming(requests, &block)
        ctx = new_context(requests.size)

        run_concurrent(requests) do |request, index|
          execute_single_request(request, index, ctx, &block)
        end

        failure_strategy.finalize(ctx[:results], ctx[:errors], preserve_order?)
      end

      # Concurrency harness — owns Async primitives, backpressure,
      # and barrier lifecycle.  Yields each (request, index) pair
      # inside a fiber governed by the semaphore.
      #
      # Swap this method to change the concurrency backend without
      # touching request dispatch or result collection.
      def run_concurrent(requests)
        max_concurrent = options[:max_inflight] || DEFAULT_MAX_INFLIGHT
        semaphore = Async::Semaphore.new(max_concurrent)
        barrier = Async::Barrier.new

        Sync do
          requests.each_with_index do |request, index|
            barrier.async do
              semaphore.acquire do
                yield request, index
              end
            end
          end

          barrier.wait
        ensure
          barrier.stop
        end
      end

      # Execution context for collecting results and errors
      def new_context(size)
        {
          results: (options[:order] == :preserve) ? Array.new(size) : [],
          errors: []
        }
      end

      def execute_single_request(request, index, ctx, &block)
        response = execute_with_retry(request, index)

        if transport_success?(response)
          store_result(response, index, ctx[:results], &block)
        else
          handle_failed_response(response, request, index, ctx, &block)
        end
      rescue => error
        handle_exception(error, request, index, ctx, &block)
      end

      def execute_request(request)
        Async::Task.current.with_timeout(request_timeout_seconds) do
          adapter.execute([request]).first
        end
      end

      # Handle a non-success HTTP response (status 0 / transport failure).
      def handle_failed_response(response, request, index, ctx, &block)
        errors = ctx[:errors]
        failure_strategy.apply(
          index: index, source: response, request: request,
          results: ctx[:results], errors: errors,
          failure: serialize_failure(response, request, index),
          raise_error: ApiClient::FanOutError.new([response], errors),
          preserve_order: preserve_order?, &block
        )
      end

      # Handle an exception raised during request execution.
      def handle_exception(error, request, index, ctx, &block)
        error_info = serialize_failure(error, request, index)
        instrument_error(error_info)
        failure_strategy.apply(
          index: index, source: error, request: request,
          results: ctx[:results], errors: ctx[:errors],
          failure: error_info, raise_error: error,
          preserve_order: preserve_order?, &block
        )
      end

      def execute_with_retry(request, index)
        retry_config = options[:retries]
        return execute_request(request) unless retry_config

        max_attempts = retry_config.fetch(:max, 0) + 1
        backoff_strategy = retry_config.fetch(:backoff, :exponential)

        max_attempts.times do |zero_based|
          attempt = zero_based + 1
          last_attempt = attempt >= max_attempts

          response = begin
            execute_request(request)
          rescue *RETRYABLE_EXCEPTIONS => error
            raise error if last_attempt
            nil
          end

          return response if response && (transport_success?(response) || last_attempt)

          instrument_retry(index, attempt, max_attempts)
          async_sleep(calculate_backoff(attempt, backoff_strategy))
        end
      end

      # Fiber-aware sleep — yields to the Async scheduler instead
      # of blocking the underlying thread.
      def async_sleep(seconds)
        Async::Task.current.sleep(seconds)
      end

      # Did the request reach the server and get an HTTP response back?
      #
      # Any HTTP status (including 4xx/5xx) counts as a successful
      # transport — only status 0 (synthetic timeout/error responses)
      # is treated as a transport-level failure eligible for retry
      # and on_fail handling.
      def transport_success?(response)
        response && response.status > 0
      end

      def preserve_order?
        options[:order] == :preserve
      end

      def store_result(response, index, results, &block)
        if preserve_order?
          results[index] = response
        else
          results << response
        end

        block&.call(response, index)
      end

      def calculate_backoff(attempt, strategy)
        max_cap = options[:max_backoff] || DEFAULT_MAX_BACKOFF

        base_delay = case strategy
        when :linear then 0.5 * attempt
        when :exponential then 0.5 * (2**(attempt - 1))
        else 0.5
        end

        jitter = base_delay * 0.25 * (prng.rand * 2 - 1)
        [base_delay + jitter, max_cap].min
      end

      # Instance-scoped PRNG — fiber-safe, no global state contention.
      attr_reader :prng

      # Serialize a failure into a structured hash for co-debugging.
      # Keeps: exception identity, message, top 5 backtrace frames,
      # request method/url, and the index for correlation.
      #
      # Raw exception is preserved under :raw for programmatic access
      # (e.g. re-raise in :fail_fast). Cleared in finalize_results to
      # avoid anchoring exception graphs in long-lived error lists.
      #
      # NOTE: Messages and URLs are stored as-is. Callers must not
      # include credentials in request URLs or exception messages.
      # If credential scrubbing is needed in the future, adopt a
      # dedicated gem rather than maintaining custom regex patterns.
      def serialize_failure(failure, request, index)
        base = {
          index: index,
          request_method: request[:method],
          request_url: request[:url],
          at: Process.clock_gettime(Process::CLOCK_REALTIME)
        }

        if failure.is_a?(Exception)
          serialize_exception(base, failure)
        else
          serialize_response(base, failure)
        end
      end

      def serialize_exception(base, error)
        base.merge(
          kind: :exception,
          error_class: error.class.name,
          message: error.message.to_s[0, 500],
          backtrace: (error.backtrace || []).first(5),
          raw: error
        )
      end

      def serialize_response(base, response)
        base.merge(
          kind: :response,
          status: response.respond_to?(:status) ? response.status : nil,
          response: response
        )
      end

      def instrument_start(count)
        Hooks.instrument(:fan_out_start,
          count: count, max_inflight: options[:max_inflight],
          on_ready: options[:on_ready], order: options[:order])
      end

      def instrument_complete(input_count, output_count, duration)
        Hooks.instrument(:fan_out_complete,
          input_count: input_count, output_count: output_count, duration: duration)
      end

      def instrument_retry(index, attempt, max_attempts)
        Hooks.instrument(:fan_out_retry, index: index, attempt: attempt, max_attempts: max_attempts)
      end

      def instrument_error(error_info)
        Hooks.instrument(:fan_out_error,
          index: error_info[:index], error_class: error_info[:error_class],
          message: error_info[:message], strategy: failure_strategy.strategy)
      end
    end
  end
end
