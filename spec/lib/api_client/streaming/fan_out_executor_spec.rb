require "spec_helper"
require "api_client"
require "api_client/adapters/concurrent_adapter"
require "faraday"

# FanOutExecutor specs test complex async streaming pipelines.
# rubocop:disable RSpec/ExampleLength, RSpec/MultipleExpectations, RSpec/MultipleMemoizedHelpers
# rubocop:disable RSpec/NestedGroups, RSpec/AnyInstance
RSpec.describe ApiClient::Streaming::FanOutExecutor do
  let(:config) { ApiClient.configuration }
  let(:adapter) { instance_double(ApiClient::Adapters::ConcurrentAdapter) }
  let(:executor) { described_class.new(config, adapter) }

  describe "constants" do
    it "defines DEFAULT_MAX_INFLIGHT based on processor count" do
      expected = (Etc.nprocessors * 1.414213562).round
      expect(described_class::DEFAULT_MAX_INFLIGHT).to eq(expected)
    end

    it "defines DEFAULT_RETRY with exponential backoff" do
      expect(described_class::DEFAULT_RETRY).to eq({backoff: :exponential})
    end

    it "defines DEFAULT_MAX_BACKOFF as 30 seconds" do
      expect(described_class::DEFAULT_MAX_BACKOFF).to eq(30)
    end

    it "defines DEFAULT_MAX_TIMEOUT_MS as 600_000" do
      expect(described_class::DEFAULT_MAX_TIMEOUT_MS).to eq(600_000)
    end

    it "defines RETRYABLE_EXCEPTIONS as a frozen array" do
      expect(described_class::RETRYABLE_EXCEPTIONS).to include(
        Async::TimeoutError,
        Errno::ECONNREFUSED,
        SocketError,
        IOError
      )
      expect(described_class::RETRYABLE_EXCEPTIONS).to be_frozen
    end
  end

  describe "#initialize" do
    it "stores config and adapter" do
      expect(executor.config).to eq(config)
      expect(executor.adapter).to eq(adapter)
    end

    it "initializes an instance-scoped PRNG" do
      prng = executor.send(:prng)
      expect(prng).to be_a(Random)
    end

    it "creates independent PRNGs per instance" do
      other = described_class.new(config, adapter)
      expect(executor.send(:prng)).not_to equal(other.send(:prng))
    end

    it "normalizes options with defaults" do
      expect(executor.options[:on_ready]).to eq(:stream)
      expect(executor.failure_strategy.strategy).to eq(:fail_fast)
      expect(executor.options[:order]).to eq(:preserve)
      expect(executor.options[:max_inflight]).to eq(described_class::DEFAULT_MAX_INFLIGHT)
      expect(executor.options[:retries]).to eq({backoff: :exponential})
    end

    it "accepts custom options" do
      custom = described_class.new(config, adapter,
        on_ready: :batch,
        on_fail: :skip,
        order: :arrival,
        max_inflight: 10,
        timeout_ms: 5000,
        retries: {max: 3, backoff: :linear})

      expect(custom.options[:on_ready]).to eq(:batch)
      expect(custom.failure_strategy.strategy).to eq(:skip)
      expect(custom.options[:order]).to eq(:arrival)
      expect(custom.options[:max_inflight]).to eq(10)
      expect(custom.options[:timeout_ms]).to eq(5000)
      expect(custom.options[:retries]).to eq({backoff: :linear, max: 3})
      expect(custom.options[:max_backoff]).to eq(described_class::DEFAULT_MAX_BACKOFF)
    end

    it "accepts custom max_backoff" do
      custom = described_class.new(config, adapter, max_backoff: 60)
      expect(custom.options[:max_backoff]).to eq(60)
    end

    it "disables retries when false" do
      no_retry = described_class.new(config, adapter, retries: false)
      expect(no_retry.options[:retries]).to be_nil
    end

    it "disables retries when nil" do
      no_retry = described_class.new(config, adapter, retries: nil)
      expect(no_retry.options[:retries]).to be_nil
    end

    context "with timeout_ms validation" do
      it "raises ArgumentError for non-numeric timeout_ms" do
        expect {
          described_class.new(config, adapter, timeout_ms: "fast")
        }.to raise_error(ArgumentError, /timeout_ms must be a positive number/)
      end

      it "raises ArgumentError for zero timeout_ms" do
        expect {
          described_class.new(config, adapter, timeout_ms: 0)
        }.to raise_error(ArgumentError, /timeout_ms must be a positive number/)
      end

      it "raises ArgumentError for negative timeout_ms" do
        expect {
          described_class.new(config, adapter, timeout_ms: -100)
        }.to raise_error(ArgumentError, /timeout_ms must be a positive number/)
      end

      it "clamps timeout_ms to DEFAULT_MAX_TIMEOUT_MS when exceeded" do
        executor = described_class.new(config, adapter, timeout_ms: 999_999)
        expect(executor.options[:timeout_ms]).to eq(described_class::DEFAULT_MAX_TIMEOUT_MS)
      end

      it "preserves valid timeout_ms" do
        executor = described_class.new(config, adapter, timeout_ms: 5000)
        expect(executor.options[:timeout_ms]).to eq(5000)
      end
    end
  end

  describe "#execute" do
    it "returns empty array for empty requests" do
      expect(executor.execute([])).to eq([])
    end

    context "with input validation" do
      it "raises ArgumentError for non-array input" do
        expect {
          executor.execute("not an array")
        }.to raise_error(ArgumentError, /requests must be an Array/)
      end

      it "raises ArgumentError for nil input" do
        expect {
          executor.execute(nil)
        }.to raise_error(ArgumentError, /requests must be an Array/)
      end

      it "raises ArgumentError when elements are not Hash-like" do
        expect {
          executor.execute(["string", "elements"])
        }.to raise_error(ArgumentError, /each request must be Hash-like/)
      end

      it "accepts empty array without validation error" do
        expect(executor.execute([])).to eq([])
      end
    end

    context "with :batch on_ready" do
      let(:batch_executor) { described_class.new(config, adapter, on_ready: :batch) }
      let(:requests) { [{path: "/a"}, {path: "/b"}] }
      let(:responses) do
        [
          instance_double(Faraday::Response, status: 200, body: "a"),
          instance_double(Faraday::Response, status: 200, body: "b")
        ]
      end

      it "delegates to adapter.execute" do
        allow(adapter).to receive(:execute).with(requests).and_return(responses)
        result = batch_executor.execute(requests)
        expect(result).to eq(responses)
        expect(adapter).to have_received(:execute).with(requests)
      end
    end

    context "with :stream on_ready", if: defined?(Async) do
      let(:stream_executor) {
        described_class.new(
          config, adapter, on_ready: :stream, retries: false
        )
      }
      let(:requests) { [{path: "/a"}, {path: "/b"}] }

      before do
        allow(adapter).to receive(:execute) do |reqs|
          reqs.map { |r| instance_double(Faraday::Response, status: 200, body: r[:path]) }
        end
      end

      it "executes requests concurrently" do
        results = stream_executor.execute(requests)
        expect(results.size).to eq(2)
      end

      it "yields to block for each response" do
        yielded = []
        stream_executor.execute(requests) do |response, index|
          yielded << [response.body, index]
        end
        expect(yielded.size).to eq(2)
      end

      it "preserves order when order: :preserve" do
        preserve_executor = described_class.new(
          config, adapter, on_ready: :stream, order: :preserve, retries: false
        )
        results = preserve_executor.execute(requests)
        expect(results.map(&:body)).to eq(["/a", "/b"])
      end
    end
  end

  describe "hooks integration" do
    let(:batch_executor) { described_class.new(config, adapter, on_ready: :batch) }
    let(:requests) { [{path: "/test"}] }
    let(:response) { instance_double(Faraday::Response, status: 200, body: "ok") }

    before do
      allow(adapter).to receive(:execute).and_return([response])
    end

    it "instruments fan_out_start" do
      events = []
      subscriber = ApiClient::Hooks.subscribe(:fan_out_start) do |*args|
        events << ActiveSupport::Notifications::Event.new(*args)
      end

      batch_executor.execute(requests)

      expect(events.size).to eq(1)
      expect(events.first.payload).to include(count: 1, on_ready: :batch)
    ensure
      ApiClient::Hooks.unsubscribe(subscriber)
    end

    it "instruments fan_out_complete" do
      events = []
      subscriber = ApiClient::Hooks.subscribe(:fan_out_complete) do |*args|
        events << ActiveSupport::Notifications::Event.new(*args)
      end

      batch_executor.execute(requests)

      expect(events.size).to eq(1)
      expect(events.first.payload).to include(input_count: 1, output_count: 1)
    ensure
      ApiClient::Hooks.unsubscribe(subscriber)
    end
  end

  describe "private methods" do
    describe "#normalize_retry" do
      it "returns nil for false" do
        result = executor.send(:normalize_retry, false)
        expect(result).to be_nil
      end

      it "returns nil for nil" do
        result = executor.send(:normalize_retry, nil)
        expect(result).to be_nil
      end

      it "merges hash with defaults" do
        result = executor.send(:normalize_retry, {max: 5})
        expect(result).to eq({backoff: :exponential, max: 5})
      end

      it "returns defaults for non-hash truthy values" do
        result = executor.send(:normalize_retry, true)
        expect(result).to eq({backoff: :exponential})
      end
    end

    describe "#calculate_backoff" do
      it "calculates linear backoff" do
        result = executor.send(:calculate_backoff, 3, :linear)
        # 0.5 * 3 = 1.5, with ±25% jitter
        expect(result).to be_between(1.125, 1.875)
      end

      it "calculates exponential backoff" do
        result = executor.send(:calculate_backoff, 3, :exponential)
        # 0.5 * 2^2 = 2.0, with ±25% jitter
        expect(result).to be_between(1.5, 2.5)
      end

      it "uses constant backoff for unknown strategy" do
        result = executor.send(:calculate_backoff, 5, :unknown)
        # 0.5 with ±25% jitter
        expect(result).to be_between(0.375, 0.625)
      end

      it "caps backoff at max_backoff option" do
        result = executor.send(:calculate_backoff, 10, :exponential)
        # 0.5 * 2^9 = 256, capped at DEFAULT_MAX_BACKOFF (30)
        expect(result).to be <= 30
      end

      it "respects custom max_backoff" do
        custom = described_class.new(config, adapter, max_backoff: 10)
        result = custom.send(:calculate_backoff, 10, :exponential)
        expect(result).to be <= 10
      end

      it "uses instance PRNG instead of Kernel#rand" do
        prng = executor.send(:prng)
        allow(prng).to receive(:rand).and_return(0.5)
        executor.send(:calculate_backoff, 1, :exponential)
        expect(prng).to have_received(:rand)
      end

      it "produces deterministic jitter with seeded PRNG" do
        seeded_a = described_class.new(config, adapter)
        seeded_b = described_class.new(config, adapter)

        # Seed both identically
        allow(seeded_a).to receive(:prng).and_return(Random.new(42))
        allow(seeded_b).to receive(:prng).and_return(Random.new(42))

        result_a = seeded_a.send(:calculate_backoff, 3, :exponential)
        result_b = seeded_b.send(:calculate_backoff, 3, :exponential)
        expect(result_a).to eq(result_b)
      end
    end

    describe "#transport_success?" do
      it "returns true for status > 0" do
        response = instance_double(Faraday::Response, status: 200)
        expect(executor.send(:transport_success?, response)).to be true
      end

      it "returns true for 4xx/5xx status" do
        response = instance_double(Faraday::Response, status: 500)
        expect(executor.send(:transport_success?, response)).to be true
      end

      it "returns false for status 0 (network failure)" do
        response = instance_double(Faraday::Response, status: 0)
        expect(executor.send(:transport_success?, response)).to be false
      end

      it "returns false for nil response" do
        expect(executor.send(:transport_success?, nil)).to be_falsey
      end
    end

    describe "#serialize_failure" do
      let(:request) { {method: :get, url: "/users"} }

      context "with an exception" do
        subject(:info) { executor.send(:serialize_failure, error, request, 3) }

        let(:error) do
          raise "connection refused"
        rescue => e
          e
        end

        it "sets kind to :exception" do
          expect(info[:kind]).to eq(:exception)
        end

        it "captures error class name" do
          expect(info[:error_class]).to eq("RuntimeError")
        end

        it "captures message" do
          expect(info[:message]).to eq("connection refused")
        end

        it "truncates message to 500 chars" do
          long_error = RuntimeError.new("x" * 1000)
          result = executor.send(:serialize_failure, long_error, request, 0)
          expect(result[:message].length).to eq(500)
        end

        it "captures top 5 backtrace frames" do
          expect(info[:backtrace]).to be_an(Array)
          expect(info[:backtrace].size).to be <= 5
        end

        it "handles nil backtrace" do
          bare_error = RuntimeError.new("no trace")
          result = executor.send(:serialize_failure, bare_error, request, 0)
          expect(result[:backtrace]).to eq([])
        end

        it "preserves raw exception for programmatic access" do
          expect(info[:raw]).to equal(error)
        end

        it "captures request identity" do
          expect(info[:request_method]).to eq(:get)
          expect(info[:request_url]).to eq("/users")
        end

        it "captures index" do
          expect(info[:index]).to eq(3)
        end

        it "includes numeric timestamp (CLOCK_REALTIME)" do
          expect(info[:at]).to be_a(Float)
        end
      end

      context "with a failed response" do
        subject(:info) { executor.send(:serialize_failure, response, request, 1) }

        let(:response) { instance_double(Faraday::Response, status: 0) }

        it "sets kind to :response" do
          expect(info[:kind]).to eq(:response)
        end

        it "captures HTTP status" do
          expect(info[:status]).to eq(0)
        end

        it "preserves raw response" do
          expect(info[:response]).to equal(response)
        end

        it "captures request identity" do
          expect(info[:request_method]).to eq(:get)
          expect(info[:request_url]).to eq("/users")
        end

        it "handles objects without status method" do
          plain = Object.new
          result = executor.send(:serialize_failure, plain, request, 0)
          expect(result[:kind]).to eq(:response)
          expect(result[:status]).to be_nil
        end
      end
    end

    describe "FailureStrategy#finalize :raw cleanup" do
      it "removes :raw references from error entries" do
        error = RuntimeError.new("test")
        errors = [{kind: :exception, raw: error, message: "test"}]
        results = [nil]

        strategy = ApiClient::Streaming::FailureStrategy.skip
        strategy.finalize(results, errors, true)

        expect(errors.first).not_to have_key(:raw)
      end
    end

    describe "FailureStrategy#finalize with arrival order" do
      it "compacts nil entries from arrival-order results" do
        response = instance_double(Faraday::Response, status: 200)
        results = [response, nil, response]
        errors = []

        strategy = ApiClient::Streaming::FailureStrategy.skip
        result = strategy.finalize(results, errors, false)

        expect(result.size).to eq(2)
        expect(result).to all(eq(response))
      end
    end
  end

  describe "streaming error handling", if: defined?(Async) do
    let(:config) { ApiClient.configuration }
    let(:adapter) { instance_double(ApiClient::Adapters::ConcurrentAdapter) }

    describe "handle_failure paths" do
      context "with :skip on_fail" do
        let(:executor) {
          described_class.new(
            config, adapter, on_ready: :stream, on_fail: :skip, retries: false
          )
        }

        it "skips failed responses" do
          allow(adapter).to receive(:execute) do |reqs|
            reqs.map do |r|
              status = (r[:path] == "/fail") ? 0 : 200
              instance_double(Faraday::Response, status: status, body: r[:path])
            end
          end

          results = executor.execute([{path: "/ok"}, {path: "/fail"}])
          expect(results.size).to eq(2)
          expect(results[0].body).to eq("/ok")
          expect(results[1]).to be_nil
        end
      end

      context "with :collect on_fail" do
        let(:executor) {
          described_class.new(
            config, adapter, on_ready: :stream, on_fail: :collect, retries: false
          )
        }

        it "collects failures and raises FanOutError" do
          allow(adapter).to receive(:execute) do |reqs|
            reqs.map do |r|
              status = (r[:path] == "/fail") ? 0 : 200
              instance_double(Faraday::Response, status: status, body: r[:path])
            end
          end

          expect {
            executor.execute([{path: "/ok"}, {path: "/fail"}])
          }.to raise_error(ApiClient::FanOutError)
        end
      end

      context "with :fail_fast on_fail" do
        let(:executor) {
          described_class.new(
            config, adapter, on_ready: :stream, on_fail: :fail_fast, retries: false
          )
        }

        it "raises on first failure" do
          allow(adapter).to receive(:execute) do |reqs|
            reqs.map do |r|
              status = (r[:path] == "/fail") ? 0 : 200
              instance_double(Faraday::Response, status: status, body: r[:path])
            end
          end

          expect {
            executor.execute([{path: "/fail"}, {path: "/ok"}])
          }.to raise_error(ApiClient::FanOutError)
        end
      end

      context "with Proc on_fail" do
        it "calls proc with response and request for failures" do
          fallback_proc = ->(response, request) {
            instance_double(Faraday::Response, status: 999, body: "fallback")
          }
          executor = described_class.new(
            config, adapter, on_ready: :stream, on_fail: fallback_proc, retries: false
          )

          allow(adapter).to receive(:execute) do |reqs|
            reqs.map do |r|
              status = (r[:path] == "/fail") ? 0 : 200
              instance_double(Faraday::Response, status: status, body: r[:path])
            end
          end

          results = executor.execute([{path: "/ok"}, {path: "/fail"}])
          expect(results.size).to eq(2)
        end

        it "skips nil fallback from proc" do
          fallback_proc = ->(_response, _request) {}
          executor = described_class.new(
            config, adapter, on_ready: :stream, on_fail: fallback_proc, retries: false
          )

          allow(adapter).to receive(:execute) do |reqs|
            reqs.map { |r| instance_double(Faraday::Response, status: 0, body: "fail") }
          end

          results = executor.execute([{path: "/fail"}])
          expect(results.size).to eq(1)
          expect(results[0]).to be_nil
        end
      end
    end

    describe "handle_error paths (exceptions)" do
      context "with :skip on_fail" do
        let(:executor) {
          described_class.new(
            config, adapter, on_ready: :stream, on_fail: :skip, retries: false
          )
        }

        it "skips items that raise exceptions" do
          call_count = 0
          allow(adapter).to receive(:execute) do |reqs|
            call_count += 1
            raise "network error" if call_count == 1
            reqs.map { |r| instance_double(Faraday::Response, status: 200, body: "ok") }
          end

          results = executor.execute([{path: "/a"}])
          expect(results).to be_an(Array)
        end
      end
    end

    describe "arrival order" do
      let(:executor) {
        described_class.new(
          config, adapter, on_ready: :stream, order: :arrival, retries: false
        )
      }

      it "stores results in arrival order" do
        allow(adapter).to receive(:execute) do |reqs|
          reqs.map { |r| instance_double(Faraday::Response, status: 200, body: r[:path]) }
        end

        results = executor.execute([{path: "/a"}, {path: "/b"}])
        expect(results.size).to eq(2)
      end
    end

    describe "Proc on_ready" do
      it "uses proc as streaming callback" do
        yielded = []
        on_ready_proc = proc { |response, index| yielded << [response.body, index] }
        executor = described_class.new(config, adapter, on_ready: on_ready_proc, retries: false)

        allow(adapter).to receive(:execute) do |reqs|
          reqs.map { |r| instance_double(Faraday::Response, status: 200, body: r[:path]) }
        end

        executor.execute([{path: "/a"}])
        expect(yielded.size).to eq(1)
      end
    end

    describe "retry logic" do
      it "retries failed requests up to max attempts" do
        attempt_count = 0
        executor = described_class.new(
          config, adapter, on_ready: :stream, retries: {max: 2, backoff: :linear}
        )

        allow(adapter).to receive(:execute) do |reqs|
          attempt_count += 1
          status = (attempt_count >= 3) ? 200 : 0
          reqs.map { |r| instance_double(Faraday::Response, status: status, body: r[:path]) }
        end

        allow_any_instance_of(described_class).to receive(:async_sleep)

        results = executor.execute([{path: "/retry-me"}])
        expect(results.size).to eq(1)
        expect(results.first.status).to eq(200)
      end

      it "instruments retry events" do
        events = []
        subscriber = ApiClient::Hooks.subscribe(:fan_out_retry) do |*args|
          events << ActiveSupport::Notifications::Event.new(*args)
        end

        attempt_count = 0
        executor = described_class.new(
          config, adapter, on_ready: :stream, retries: {max: 1, backoff: :exponential}
        )

        allow(adapter).to receive(:execute) do |reqs|
          attempt_count += 1
          status = (attempt_count >= 2) ? 200 : 0
          reqs.map { |r| instance_double(Faraday::Response, status: status, body: r[:path]) }
        end

        allow_any_instance_of(described_class).to receive(:async_sleep)

        executor.execute([{path: "/retry-me"}])
        expect(events.size).to eq(1)
        expect(events.first.payload).to include(:index, :attempt, :max_attempts)
      ensure
        ApiClient::Hooks.unsubscribe(subscriber)
      end

      it "retries retryable exceptions and succeeds on later attempt" do
        attempt_count = 0
        executor = described_class.new(
          config, adapter, on_ready: :stream, retries: {max: 2, backoff: :linear}
        )

        allow(adapter).to receive(:execute) do |reqs|
          attempt_count += 1
          raise Errno::ECONNREFUSED if attempt_count < 3
          reqs.map { |r| instance_double(Faraday::Response, status: 200, body: r[:path]) }
        end

        allow_any_instance_of(described_class).to receive(:async_sleep)

        results = executor.execute([{path: "/retry-ex"}])
        expect(results.size).to eq(1)
        expect(results.first.status).to eq(200)
        expect(attempt_count).to eq(3)
      end

      it "raises retryable exception when all attempts exhausted" do
        executor = described_class.new(
          config, adapter, on_ready: :stream, on_fail: :fail_fast, retries: {max: 1, backoff: :linear}
        )

        allow(adapter).to receive(:execute).and_raise(Errno::ECONNREFUSED)
        allow_any_instance_of(described_class).to receive(:async_sleep)

        expect {
          executor.execute([{path: "/always-fail"}])
        }.to raise_error(Errno::ECONNREFUSED)
      end
    end

    describe "timeout fallback to config.read_timeout" do
      it "uses config.read_timeout when timeout_ms is not set" do
        executor = described_class.new(config, adapter, on_ready: :stream, retries: false)

        allow(adapter).to receive(:execute) do |reqs|
          reqs.map { |r| instance_double(Faraday::Response, status: 200, body: r[:path]) }
        end

        results = executor.execute([{path: "/a"}])
        expect(results.size).to eq(1)
      end
    end

    describe "error handling with exceptions" do
      context "with :fail_fast on_fail and exceptions" do
        it "re-raises the original exception" do
          executor = described_class.new(
            config, adapter, on_ready: :stream, on_fail: :fail_fast, retries: false
          )

          allow(adapter).to receive(:execute).and_raise(RuntimeError, "kaboom")

          expect {
            executor.execute([{path: "/fail"}])
          }.to raise_error(RuntimeError, "kaboom")
        end
      end

      context "with Proc on_fail and exceptions" do
        it "calls proc with error and request" do
          called_with = nil
          fallback_proc = ->(error, request) {
            called_with = {error: error, request: request}
            instance_double(Faraday::Response, status: 999, body: "fallback")
          }
          executor = described_class.new(
            config, adapter, on_ready: :stream, on_fail: fallback_proc, retries: false
          )

          allow(adapter).to receive(:execute).and_raise("network failure")

          executor.execute([{path: "/fail"}])
          expect(called_with).not_to be_nil
          expect(called_with[:request]).to eq({path: "/fail"})
        end

        it "skips nil fallback from proc on exception" do
          fallback_proc = ->(_error, _request) {}
          executor = described_class.new(
            config, adapter, on_ready: :stream, on_fail: fallback_proc, retries: false
          )

          allow(adapter).to receive(:execute).and_raise("network failure")

          results = executor.execute([{path: "/fail"}])
          expect(results.size).to eq(1)
          expect(results[0]).to be_nil
        end
      end

      context "with :collect on_fail and exceptions" do
        it "collects exception errors and raises FanOutError" do
          executor = described_class.new(
            config, adapter, on_ready: :stream, on_fail: :collect, retries: false
          )

          allow(adapter).to receive(:execute).and_raise("network failure")

          expect {
            executor.execute([{path: "/fail"}])
          }.to raise_error(ApiClient::FanOutError)
        end
      end
    end
  end

  describe ApiClient::FanOutError do
    subject(:error) { described_class.new(results, failures) }

    let(:results) { [instance_double(Faraday::Response, status: 200)] }
    let(:failures) do
      [{
        index: 1,
        request_method: :get,
        request_url: "/fail",
        at: Time.now.utc.iso8601(3),
        kind: :exception,
        error_class: "StandardError",
        message: "boom",
        backtrace: [],
        raw: StandardError.new("boom")
      }]
    end

    it "inherits from ProcessingError" do
      expect(error).to be_a(ApiClient::ProcessingError)
    end

    it "stores partial results" do
      expect(error.partial_results).to eq(results)
    end

    it "stores serialized failures" do
      expect(error.failures.first[:kind]).to eq(:exception)
      expect(error.failures.first[:error_class]).to eq("StandardError")
      expect(error.failures.first[:message]).to eq("boom")
      expect(error.failures.first[:index]).to eq(1)
    end

    it "includes FanOut in message" do
      expect(error.message).to include("FanOut")
    end

    it "reports success_count" do
      expect(error.success_count).to eq(1)
    end

    it "reports failure_count" do
      expect(error.failure_count).to eq(1)
    end
  end
end
# rubocop:enable RSpec/ExampleLength, RSpec/MultipleExpectations, RSpec/MultipleMemoizedHelpers
# rubocop:enable RSpec/NestedGroups, RSpec/AnyInstance
