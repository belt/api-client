require_relative "../hooks"

module ApiClient
  module Adapters
    # Shared instrumentation for batch HTTP adapters
    #
    # Provides standardized timing and hooks for batch request execution.
    # Include this module in adapter implementations to reduce duplication.
    #
    # @example Including in an adapter
    #   class MyAdapter
    #     include Base
    #     include Instrumentation
    #
    #     def execute(requests)
    #       with_batch_instrumentation(:my_adapter, requests) do
    #         # Execute requests and return results
    #       end
    #     end
    #   end
    #
    module Instrumentation
      # Execute block with batch instrumentation
      #
      # Instruments batch_start, batch_complete, and batch_slow events.
      # Calculates success count from results.
      #
      # @param adapter_name [Symbol] Adapter identifier for events
      # @param requests [Array<Hash>] Request specifications
      # @yield Block that executes requests and returns results array
      # @return [Array] Results from block
      def with_batch_instrumentation(adapter_name, requests)
        Hooks.instrument(:batch_start, adapter: adapter_name, count: requests.size)
        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        results = yield

        duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
        duration_ms = (duration * 1000).round

        instrument_batch_complete(adapter_name, requests.size, results, duration)
        instrument_batch_slow(adapter_name, requests.size, duration_ms)

        results
      end

      private

      def instrument_batch_complete(adapter_name, count, results, duration)
        success_count = results.count do |response|
          response.respond_to?(:status) && response.status >= 200 && response.status < 300
        end

        Hooks.instrument(:batch_complete,
          adapter: adapter_name,
          count: count,
          duration: duration,
          success_count: success_count)
      end

      def instrument_batch_slow(adapter_name, count, duration_ms)
        threshold = config.batch_slow_threshold_ms
        return unless duration_ms >= threshold

        Hooks.instrument(:batch_slow,
          adapter: adapter_name,
          count: count,
          duration_ms: duration_ms,
          threshold_ms: threshold)
      end
    end
  end
end
