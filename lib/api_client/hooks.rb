require "active_support/notifications"

module ApiClient
  # Hook dispatch via ActiveSupport::Notifications
  #
  # Provides instrumentation for request lifecycle events.
  # Custom hooks registered via Configuration are also dispatched.
  #
  # @example Subscribe to events
  #   ActiveSupport::Notifications.subscribe('api_client.request.complete') do |*args|
  #     event = ActiveSupport::Notifications::Event.new(*args)
  #     Rails.logger.info(
  #       "#{event.payload[:method]} #{event.payload[:url]} " \
  #       "- #{event.payload[:status]}"
  #     )
  #   end
  #
  # @example Custom hooks via configuration
  #   ApiClient.configure do |config|
  #     config.on(:request_complete) { |payload| StatsD.increment('api.request') }
  #   end
  #
  module Hooks
    NAMESPACE = "api_client"

    # Event name mapping
    EVENTS = {
      # Request lifecycle
      request_start: "request.start",
      request_complete: "request.complete",
      request_error: "request.error",
      request_slow: "request.slow",

      # Batch operations (adapters/orchestrators)
      batch_start: "batch.start",
      batch_complete: "batch.complete",
      batch_slow: "batch.slow",
      batch_error: "batch.error",

      # Circuit breaker
      circuit_open: "circuit.open",
      circuit_close: "circuit.close",
      circuit_half_open: "circuit.half_open",
      circuit_error: "circuit.error",
      circuit_rejected: "circuit.rejected",
      circuit_fallback: "circuit.fallback",

      # Connection
      connection_reconnect: "connection.reconnect",

      # URI policy
      request_blocked: "request.blocked",

      # Profiling
      profile_captured: "profile.captured",

      # RequestFlow
      request_flow_start: "request_flow.start",
      request_flow_complete: "request_flow.complete",
      request_flow_step: "request_flow.step",

      # Ractor processor
      ractor_start: "ractor.start",
      ractor_complete: "ractor.complete",
      ractor_error: "ractor.error",

      # Async processor
      async_processor_start: "async_processor.start",
      async_processor_complete: "async_processor.complete",
      async_processor_error: "async_processor.error",

      # Concurrent processor
      concurrent_processor_start: "concurrent_processor.start",
      concurrent_processor_complete: "concurrent_processor.complete",
      concurrent_processor_error: "concurrent_processor.error",

      # Fan-out streaming
      fan_out_start: "fan_out.start",
      fan_out_complete: "fan_out.complete",
      fan_out_retry: "fan_out.retry",
      fan_out_error: "fan_out.error",

      # Pool metrics
      pool_stats: "pool.stats"
    }.freeze

    # Pre-computed full event names: avoids string interpolation + hash
    # fetch on every instrument call (hot path: 2-3 calls per request).
    FULL_EVENT_NAMES = EVENTS.each_with_object({}) { |(key, suffix), h|
      h[key] = "#{NAMESPACE}.#{suffix}".freeze
    }.freeze

    class << self
      # Instrument an event
      # @param event [Symbol] Event name (e.g., :request_start)
      # @param payload [Hash] Event payload
      def instrument(event, payload = {})
        event_name = FULL_EVENT_NAMES[event] || full_event_name(event)

        # Fast path: skip block overhead when no custom hooks registered.
        # AS::Notifications.instrument without a block is cheaper (no
        # block allocation, no yield). Custom hooks are the uncommon case.
        if ApiClient.configuration.has_hooks?
          ActiveSupport::Notifications.instrument(event_name, payload) do
            dispatch_custom_hooks(event, payload)
          end
        else
          ActiveSupport::Notifications.instrument(event_name, payload)
        end
      end

      # Subscribe to an event
      # @param event [Symbol] Event name
      # @param block [Proc] Handler block
      def subscribe(event, &block)
        ActiveSupport::Notifications.subscribe(full_event_name(event), &block)
      end

      # Unsubscribe from an event
      # @param subscriber [Object] Subscriber returned from subscribe
      def unsubscribe(subscriber)
        ActiveSupport::Notifications.unsubscribe(subscriber)
      end

      private

      def full_event_name(event)
        suffix = EVENTS.fetch(event) { event.to_s }
        "#{NAMESPACE}.#{suffix}"
      end

      def dispatch_custom_hooks(event, payload)
        hooks = ApiClient.configuration.hooks_for(event)
        hooks.each { |hook| safe_call(hook, payload) }
      end

      def safe_call(hook, payload)
        hook.call(payload)
      rescue => error
        ApiClient.configuration.logger&.error do
          "ApiClient hook error: #{error.class}: #{error.message}"
        end
      end
    end
  end
end
