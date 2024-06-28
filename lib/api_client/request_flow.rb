require_relative "request_flow/registry"
require_relative "request_flow/step_helpers"
require_relative "orchestrators/batch"
require_relative "orchestrators/sequential"
require_relative "hooks"

module ApiClient
  # RequestFlow for sequential-to-parallel workflows
  #
  # Supports patterns like: fetch user → extract post_ids → fan-out fetch posts
  #
  # @example User → Posts request flow
  #   flow = RequestFlow.new(connection)
  #   posts = flow
  #     .fetch(:get, '/users/123')
  #     .then { |resp| JSON.parse(resp.body)['post_ids'] }
  #     .fan_out { |id| { method: :get, path: "/posts/#{id}" } }
  #     .collect
  #
  class RequestFlow
    attr_reader :connection, :batch_executor, :steps

    # Maximum time (seconds) for the entire flow to complete.
    # nil = no timeout (default). Set to prevent runaway flows.
    attr_accessor :flow_timeout

    # @param connection [Connection] ApiClient connection
    # @param batch_executor [Orchestrators::Batch, nil] Custom batch executor
    # @param flow_timeout [Numeric, nil] Max seconds for entire flow (nil = no limit)
    def initialize(connection, batch_executor: nil, flow_timeout: nil)
      @connection = connection
      @batch_executor = batch_executor || Orchestrators::Batch.new(connection.config)
      @steps = []
      @flow_timeout = flow_timeout
    end

    # Add a fetch step (sequential request)
    # @param method [Symbol] HTTP method
    # @param path [String] Request path
    # @param opts [Hash] Additional options (params, headers, body)
    # @return [RequestFlow] self for chaining
    def fetch(method, path, **opts)
      @steps << [:fetch, {method: method, path: path, **opts}]
      self
    end

    # Add a transform step
    # @yield [result] Transform the current result
    # @return [RequestFlow] self for chaining
    def then(&transform)
      @steps << [:transform, transform]
      self
    end

    # Add a fan-out step (concurrent requests from array)
    #
    # @param on_ready [Symbol, Proc] :stream (default), :batch, or callback Proc
    # @param on_fail [Symbol, Proc] :fail_fast (default), :skip, :collect, or Proc
    # @param order [Symbol] :preserve (default) or :arrival
    # @param max_inflight [Integer] Concurrent request limit (default: nproc * √2)
    # @param timeout_ms [Integer] Per-request timeout in milliseconds
    # @param retries [Hash, false] Retry config {max:, backoff:} or false to disable
    # @yield [item] Build request hash from each item
    # @return [RequestFlow] self for chaining
    #
    # @example Streaming with retry
    #   flow.fan_out(
    #     on_fail: :skip,
    #     timeout_ms: 5000,
    #     retries: { max: 2 }
    #   ) { |id| { method: :get, path: "/posts/#{id}" } }
    #
    # @example Batch mode (wait for all)
    #   flow.fan_out(on_ready: :batch) { |id| ... }
    #
    # @example Custom error handling
    #   flow.fan_out(on_fail: ->(err, req) { {error: err.message} }) { |id| ... }
    #
    def fan_out(on_ready: :stream, on_fail: :fail_fast, order: :preserve,
      max_inflight: nil, timeout_ms: nil, retries: {backoff: :exponential},
      &request_builder)
      @steps << [:fan_out, {
        request_builder: request_builder,
        on_ready: on_ready,
        on_fail: on_fail,
        order: order,
        max_inflight: max_inflight,
        timeout_ms: timeout_ms,
        retries: retries
      }]
      self
    end

    # Add a filter step
    # @yield [item] Filter predicate
    # @return [RequestFlow] self for chaining
    def filter(&predicate)
      @steps << [:filter, predicate]
      self
    end

    # Add a map step (transform each item in array)
    # @yield [item] Transform each item
    # @return [RequestFlow] self for chaining
    def map(&transform)
      @steps << [:map, transform]
      self
    end

    # Add a parallel map step (Ractor-powered for CPU-bound work)
    # @param recipe [Transforms::Recipe] Extraction and transformation recipe
    # @param errors [ErrorStrategy, nil] Error handling strategy
    # @yield [transformed_item] Optional block for post-transform processing
    # @return [RequestFlow] self for chaining
    def parallel_map(recipe: Transforms::Recipe.default, errors: nil, &block)
      add_processor_step(:parallel_map, recipe:, errors:, block:)
    end

    # Add an async map step (fork-based parallelism for CPU-bound work)
    # Alternative to parallel_map using async-container instead of Ractors.
    # @param recipe [Transforms::Recipe] Extraction and transformation recipe
    # @param errors [ErrorStrategy, nil] Error handling strategy
    # @yield [transformed_item] Optional block for post-transform processing
    # @return [RequestFlow] self for chaining
    def async_map(recipe: Transforms::Recipe.default, errors: nil, &block)
      add_processor_step(:async_map, recipe:, errors:, block:)
    end

    # Add a concurrent map step (thread-based parallelism for CPU-bound work)
    # Uses concurrent-ruby thread pool. Best for JRuby or mixed I/O+CPU workloads.
    # @param recipe [Transforms::Recipe] Extraction and transformation recipe
    # @param errors [ErrorStrategy, nil] Error handling strategy
    # @yield [transformed_item] Optional block for post-transform processing
    # @return [RequestFlow] self for chaining
    def concurrent_map(recipe: Transforms::Recipe.default, errors: nil, &block)
      add_processor_step(:concurrent_map, recipe:, errors:, block:)
    end

    # Add a process step (auto-detects best processor for CPU-bound work)
    # Uses Processing::Registry to detect: Ractor > Async > Concurrent > Sequential
    # @param recipe [Transforms::Recipe] Extraction and transformation recipe
    # @param errors [ErrorStrategy, nil] Error handling strategy
    # @yield [transformed_item] Optional block for post-transform processing
    # @return [RequestFlow] self for chaining
    def process(recipe: Transforms::Recipe.default, errors: nil, &block)
      add_processor_step(:process, recipe:, errors:, block:)
    end

    # Execute the request flow and return final result
    # @return [Object] Final result (varies by flow)
    # @raise [ApiClient::Error] Wraps step errors with flow context
    # @raise [ApiClient::TimeoutError] If flow_timeout exceeded
    def collect
      Hooks.instrument(:request_flow_start, step_count: @steps.size)
      flow_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      result = nil
      @steps.each_with_index do |(type, payload), index|
        check_flow_timeout!(flow_start, index)
        step_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        begin
          result = execute_step(type, payload, result)
        rescue ApiClient::Error
          raise # Already an ApiClient error, propagate as-is
        rescue => error
          raise ApiClient::Error, I18n.t("request_flow.step_failed", index: index, type: type, message: error.message)
        end

        step_duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - step_start

        Hooks.instrument(:request_flow_step,
          step_index: index,
          step_type: type,
          duration: step_duration)
      end

      duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - flow_start
      Hooks.instrument(:request_flow_complete, step_count: @steps.size, duration: duration)

      result
    end

    # Reset request flow for reuse
    # @return [RequestFlow] self
    def reset
      @steps = []
      self
    end

    private

    # Shared builder for processor steps (parallel_map, async_map, concurrent_map, process)
    def add_processor_step(type, recipe:, errors:, block:)
      @steps << [type, StepHelpers.build_processor_step_options(
        recipe: recipe, errors: errors, block: block
      )]
      self
    end

    def check_flow_timeout!(flow_start, step_index)
      return unless @flow_timeout

      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - flow_start
      return unless elapsed > @flow_timeout

      raise ApiClient::TimeoutError.new(
        :flow,
        I18n.t("request_flow.timeout", timeout: @flow_timeout, step_index: step_index, elapsed: elapsed.round(2))
      )
    end

    # Mapping from step type to processor file (lazy-loaded on first use)
    PROCESSOR_REQUIRES = {
      parallel_map: "processing/ractor_processor",
      async_map: "processing/async_processor",
      concurrent_map: "processing/concurrent_processor"
    }.freeze

    def execute_step(type, payload, current_result)
      case type
      when :fetch
        execute_fetch(payload)
      when :transform
        payload.call(current_result)
      when :fan_out
        execute_fan_out(payload, current_result)
      when :filter
        items = Array(current_result)
        items.select(&payload)
      when :map
        items = Array(current_result)
        items.map(&payload)
      when :process
        # :process uses Processing::Registry (auto-detects best CPU processor)
        # while :parallel_map/:async_map/:concurrent_map use RequestFlow::Registry
        # (explicit processor selection). Two registries because they serve
        # different purposes: Processing::Registry does runtime capability
        # detection, RequestFlow::Registry does named dispatch.
        execute_auto_process(payload, current_result)
      else
        # Named processor steps (:parallel_map, :async_map, :concurrent_map)
        # dispatched via RequestFlow::Registry (lazy-loaded on first use)
        if PROCESSOR_REQUIRES.key?(type)
          require_relative PROCESSOR_REQUIRES[type] unless Registry.processor?(type)
          execute_processor_step(type, payload, current_result)
        else
          raise ArgumentError, I18n.t("request_flow.unknown_step", type: type)
        end
      end
    end

    def execute_fetch(opts)
      Orchestrators.execute_request(connection, opts)
    end

    def execute_fan_out(opts, items)
      require_relative "streaming/fan_out_executor"

      requests = Array(items).map { |item| opts[:request_builder].call(item) }

      executor = Streaming::FanOutExecutor.new(
        connection.config,
        batch_executor.adapter,
        on_ready: opts[:on_ready],
        on_fail: opts[:on_fail],
        order: opts[:order],
        max_inflight: opts[:max_inflight],
        timeout_ms: opts[:timeout_ms],
        retries: opts[:retries]
      )

      executor.execute(requests)
    end

    def execute_processor_step(type, opts, items)
      StepHelpers.execute_processor(type, opts, Array(items), Registry)
    end

    def execute_auto_process(opts, items)
      require_relative "processing/registry"

      processor_class = Processing::Registry.resolve(Processing::Registry.detect)
      StepHelpers.execute_with_processor(processor_class, opts, Array(items))
    end
  end
end
