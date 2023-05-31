module ApiClient
  # Base error class for ApiClient
  class Error < StandardError; end

  # Raised when circuit breaker is open
  class CircuitOpenError < Error
    attr_reader :service

    def initialize(service, message = nil)
      @service = service
      super(message || I18n.t("errors.circuit_open", service: service))
    end
  end

  # Raised when no concurrency adapter is available
  class NoAdapterError < Error
    def initialize(message = nil)
      super(message || I18n.t("errors.no_adapter"))
    end
  end

  # Raised when configuration is invalid
  class ConfigurationError < Error; end

  # Raised when a URI is blocked by SSRF policy
  class SsrfBlockedError < Error
    attr_reader :uri, :reason

    def initialize(uri, reason)
      @uri = uri.to_s
      @reason = reason
      super(I18n.t("errors.ssrf_blocked", reason: reason, uri: @uri))
    end
  end

  # Raised when request times out
  class TimeoutError < Error
    attr_reader :timeout_type

    def initialize(timeout_type, message = nil)
      @timeout_type = timeout_type
      super(message || I18n.t("errors.timeout", timeout_type: timeout_type))
    end
  end

  # Base error for parallel processing failures
  class ProcessingError < Error
    attr_reader :results, :failures

    def initialize(results, failures, processor_name)
      @results = results
      @failures = failures
      super(I18n.t("errors.processing", count: failures.size, processor_name: processor_name))
    end

    def partial_results
      results.compact
    end

    def success_count
      results.count { |r| !r.nil? }
    end

    def failure_count
      failures.size
    end
  end

  # Error raised when Ractor :collect strategy encounters failures
  class RactorProcessingError < ProcessingError
    def initialize(results, failures)
      super(results, failures, "Ractor")
    end
  end

  # Error raised when AsyncProcessor :collect strategy encounters failures
  class AsyncProcessingError < ProcessingError
    def initialize(results, failures)
      super(results, failures, "AsyncProcessor")
    end
  end

  # Error raised when ConcurrentProcessor :collect strategy encounters failures
  class ConcurrentProcessingError < ProcessingError
    def initialize(results, failures)
      super(results, failures, "ConcurrentProcessor")
    end
  end

  # Error raised when streaming fan-out :collect strategy encounters failures
  class FanOutError < ProcessingError
    def initialize(results, failures)
      super(results, failures, "FanOut")
    end
  end
end
