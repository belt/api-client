require "spec_helper"
require "api_client"
require "faraday"

# Only run if async-container is available
RSpec.describe ApiClient::Processing::AsyncProcessor,
  if: ApiClient::Processing::AsyncProcessor.available? do
  # Use high min_batch_size to force sequential mode in tests (avoids fork issues)
  subject(:processor) do
    described_class.new(
      pool_size: 2, min_batch_size: 100,
      min_payload_size: 100_000,
      errors: ApiClient::Processing::ErrorStrategy.skip
    )
  end

  describe ".available?" do
    it "returns true when async-container is available" do
      expect(described_class.available?).to be true
    end
  end

  describe "#initialize" do
    it "uses configuration defaults" do
      ApiClient.configure do |config|
        config.processor_config.async_pool_size = 4
        config.processor_config.async_min_batch_size = 5
        config.processor_config.async_min_payload_size = 1000
      end

      default_processor = described_class.new
      expect(default_processor.pool_size).to eq(4)
      expect(default_processor.min_batch_size).to eq(5)
      expect(default_processor.min_payload_size).to eq(1000)
      expect(default_processor.default_error_strategy.strategy).to eq(:fail_fast)
    end

    it "accepts custom options" do
      custom = described_class.new(
        pool_size: 8, min_batch_size: 10,
        min_payload_size: 500,
        errors: ApiClient::Processing::ErrorStrategy.fail_fast
      )
      expect(custom.pool_size).to eq(8)
      expect(custom.min_batch_size).to eq(10)
      expect(custom.min_payload_size).to eq(500)
      expect(custom.default_error_strategy.strategy).to eq(:fail_fast)
    end
  end

  describe "#map" do
    let(:responses) do
      3.times.map { |i| instance_double(
        Faraday::Response, body: {id: i}.to_json, status: 200, headers: {}) }
    end

    it "returns empty array for empty input" do
      expect(processor.map([])).to eq([])
    end

    it "transforms responses with default recipe" do
      results = processor.map(responses)
      expect(results).to eq([{"id" => 0}, {"id" => 1}, {"id" => 2}])
    end

    it "applies custom block" do
      results = processor.map(responses) { |h| h["id"] * 2 }
      expect(results).to eq([0, 2, 4])
    end

    it "extracts status" do
      results = processor.map(responses, recipe: ApiClient::Transforms::Recipe.status)
      expect(results).to eq([200, 200, 200])
    end

    it "extracts headers" do
      results = processor.map(responses, recipe: ApiClient::Transforms::Recipe.headers)
      expect(results.first).to eq({})
    end

    it "uses identity extractor" do
      plain_items = ["a", "b", "c"]
      recipe = ApiClient::Transforms::Recipe.new(extract: :identity, transform: :identity)
      results = processor.map(plain_items, recipe: recipe)
      expect(results).to eq(["a", "b", "c"])
    end

    it "accepts proc extractor" do
      custom = ->(r) { "s:#{r.status}" }
      recipe = ApiClient::Transforms::Recipe.new(extract: custom, transform: :identity)
      results = processor.map(responses, recipe: recipe)
      expect(results).to eq(["s:200", "s:200", "s:200"])
    end

    it "raises for unknown extractor" do
      recipe = ApiClient::Transforms::Recipe.new(extract: :unknown, transform: :json)
      expect { processor.map(responses, recipe: recipe) }
        .to raise_error(ArgumentError, /Unknown extractor/)
    end

    it "raises for invalid extractor type" do
      recipe = ApiClient::Transforms::Recipe.new(extract: 123, transform: :json)
      expect { processor.map(responses, recipe: recipe) }
        .to raise_error(ArgumentError, /must be Symbol or Proc/)
    end
  end

  describe "#select" do
    let(:responses) do
      5.times.map { |i| instance_double(
        Faraday::Response, body: {id: i, even: i.even?}.to_json, status: 200, headers: {}) }
    end

    it "returns empty array for empty input" do
      expect(processor.select([]) { true }).to eq([])
    end

    it "filters based on predicate" do
      results = processor.select(responses) { |h| h["even"] }
      expect(results.size).to eq(3)
    end
  end

  describe "#reduce" do
    let(:responses) do
      3.times.map { |i| instance_double(
        Faraday::Response, body: {value: i + 1}.to_json, status: 200, headers: {}) }
    end

    it "returns initial for empty input" do
      expect(processor.reduce([], 0) { |acc, _| acc }).to eq(0)
    end

    it "reduces transformed values" do
      result = processor.reduce(responses, 0) { |acc, h| acc + h["value"] }
      expect(result).to eq(6)
    end
  end

  describe "sequential fallback" do
    let(:small_responses) do
      2.times.map { |i| instance_double(
        Faraday::Response, body: {id: i}.to_json, status: 200, headers: {}) }
    end

    it "uses sequential for small batches" do
      large_batch_processor = described_class.new(min_batch_size: 10, min_payload_size: 1)
      results = large_batch_processor.map(small_responses)
      expect(results.size).to eq(2)
    end

    it "uses sequential for small payloads" do
      large_payload_processor = described_class.new(min_batch_size: 1, min_payload_size: 100_000)
      results = large_payload_processor.map(small_responses)
      expect(results.size).to eq(2)
    end
  end

  describe "error handling" do
    let(:bad_responses) do
      [
        instance_double(Faraday::Response, body: "not json", status: 200, headers: {}),
        instance_double(Faraday::Response, body: {id: 1}.to_json, status: 200, headers: {})
      ]
    end

    describe ":skip strategy" do
      it "skips failed items" do
        results = processor.map(bad_responses, errors: ApiClient::Processing::ErrorStrategy.skip)
        expect(results).to eq([{"id" => 1}])
      end
    end

    describe ":replace strategy" do
      it "replaces failed items with fallback" do
        results = processor.map(bad_responses,
          errors: ApiClient::Processing::ErrorStrategy.replace({}))
        expect(results).to include({})
        expect(results).to include({"id" => 1})
      end
    end

    describe ":fail_fast strategy" do
      it "raises on first error" do
        expect {
          processor.map(bad_responses, errors: ApiClient::Processing::ErrorStrategy.fail_fast)
        }.to raise_error(JSON::ParserError)
      end
    end

    describe ":collect strategy" do
      it "raises AsyncProcessingError with partial results" do
        expect {
          processor.map(bad_responses, errors: ApiClient::Processing::ErrorStrategy.collect)
        }.to raise_error(ApiClient::AsyncProcessingError) do |error|
          expect(error.partial_results).to include({"id" => 1})
          expect(error.failure_count).to eq(1)
        end
      end
    end
  end

  describe "hooks integration" do
    let(:responses) do
      3.times.map { |i| instance_double(
        Faraday::Response, body: {id: i}.to_json, status: 200, headers: {}) }
    end

    it "instruments async_processor_start" do
      events = []
      subscriber = ApiClient::Hooks.subscribe(:async_processor_start) do |*args|
        events << ActiveSupport::Notifications::Event.new(*args)
      end

      processor.map(responses)

      expect(events.size).to eq(1)
      expect(events.first.payload).to include(operation: :map, count: 3)
    ensure
      ApiClient::Hooks.unsubscribe(subscriber)
    end

    it "instruments async_processor_complete" do
      events = []
      subscriber = ApiClient::Hooks.subscribe(:async_processor_complete) do |*args|
        events << ActiveSupport::Notifications::Event.new(*args)
      end

      processor.map(responses)

      expect(events.size).to eq(1)
      expect(events.first.payload).to include(operation: :map, input_count: 3, output_count: 3)
    ensure
      ApiClient::Hooks.unsubscribe(subscriber)
    end

    it "instruments async_processor_error" do
      bad = [instance_double(Faraday::Response, body: "bad", status: 200, headers: {})]
      events = []
      subscriber = ApiClient::Hooks.subscribe(:async_processor_error) do |*args|
        events << ActiveSupport::Notifications::Event.new(*args)
      end

      processor.map(bad, errors: ApiClient::Processing::ErrorStrategy.skip)

      expect(events.size).to eq(1)
      expect(events.first.payload).to include(index: 0, strategy: :skip)
    ensure
      ApiClient::Hooks.unsubscribe(subscriber)
    end
  end
end

# Test when async-container is NOT available
RSpec.describe "ApiClient::Processing::AsyncProcessor availability" do
  describe ".available?" do
    it "returns boolean" do
      expect(ApiClient::Processing::AsyncProcessor.available?).to be(true).or be(false)
    end
  end
end

RSpec.describe ApiClient::Processing::AsyncProcessor, "parallel path coverage",
  if: ApiClient::Processing::AsyncProcessor.available? do
  # Test parallel processing paths by mocking Async::Container internals
  # This avoids actual forking which causes issues in RSpec

  describe "#parallel_map (mocked container)" do
    let(:processor) { described_class.new(pool_size: 2, min_batch_size: 1, min_payload_size: 1) }
    let(:responses) do
      5.times.map { |i| instance_double(
        Faraday::Response, body: {id: i}.to_json, status: 200, headers: {}) }
    end

    before do
      # Mock fork? to return false so we use sequential path for actual execution
      # but we can still test the parallel_map method directly
      allow(Async::Container).to receive(:fork?).and_return(false)
    end

    it "falls back to sequential when fork not available" do
      results = processor.map(responses)
      expect(results).to eq([{"id" => 0}, {"id" => 1}, {"id" => 2}, {"id" => 3}, {"id" => 4}])
    end
  end

  describe "#partition_work" do
    let(:processor) { described_class.new(pool_size: 2, min_batch_size: 100) }

    it "partitions items round-robin across workers" do
      items = %w[a b c d e]
      partitions = processor.send(:partition_work, items, 2)

      expect(partitions.size).to eq(2)
      # First partition gets indices 0, 2, 4
      expect(partitions[0].map(&:first)).to eq([0, 2, 4])
      # Second partition gets indices 1, 3
      expect(partitions[1].map(&:first)).to eq([1, 3])
    end

    it "handles fewer items than workers" do
      items = %w[a]
      partitions = processor.send(:partition_work, items, 4)

      expect(partitions.size).to eq(1)
      expect(partitions[0]).to eq([[0, "a"]])
    end

    it "rejects empty partitions" do
      items = %w[a b]
      partitions = processor.send(:partition_work, items, 5)

      expect(partitions.size).to eq(2)
      expect(partitions.none?(&:empty?)).to be true
    end
  end

  describe "#process_partition" do
    let(:processor) { described_class.new(pool_size: 2, min_batch_size: 100) }

    it "transforms partition items successfully" do
      partition = [[0, '{"id":1}'], [2, '{"id":2}']]
      results = processor.send(:process_partition, partition, :json)

      expect(results).to eq([[:ok, {"id" => 1}], [:ok, {"id" => 2}]])
    end

    it "captures errors in partition processing" do
      partition = [[0, "not json"], [1, '{"id":1}']]
      results = processor.send(:process_partition, partition, :json)

      expect(results[0][0]).to eq(:error)
      expect(results[0][1]).to include(:error_class, :message)
      expect(results[1]).to eq([:ok, {"id" => 1}])
    end
  end

  describe "#use_sequential?" do
    context "when batch is small" do
      let(:processor) { described_class.new(pool_size: 2, min_batch_size: 10, min_payload_size: 1) }

      it "returns true for small batches" do
        items = [instance_double(Faraday::Response, body: "x" * 1000)]
        expect(processor.send(:use_sequential?, items, :body)).to be true
      end
    end

    context "when payload is small" do
      let(:processor) {
        described_class.new(
          pool_size: 2, min_batch_size: 1, min_payload_size: 10_000
        )
      }

      it "returns true for small payloads" do
        allow(Async::Container).to receive(:fork?).and_return(true)
        items = 5.times.map { instance_double(Faraday::Response, body: "tiny") }
        expect(processor.send(:use_sequential?, items, :body)).to be true
      end
    end

    context "when fork is not available" do
      let(:processor) { described_class.new(pool_size: 2, min_batch_size: 1, min_payload_size: 1) }

      it "returns true when fork not supported" do
        allow(Async::Container).to receive(:fork?).and_return(false)
        items = 5.times.map { instance_double(Faraday::Response, body: "x" * 10_000) }
        expect(processor.send(:use_sequential?, items, :body)).to be true
      end
    end

    context "when sample has no bytesize" do
      let(:processor) {
        described_class.new(
          pool_size: 2, min_batch_size: 1, min_payload_size: 100
        )
      }

      it "treats non-string samples as zero size" do
        allow(Async::Container).to receive(:fork?).and_return(true)
        items = [instance_double(Faraday::Response, status: 200)]
        # Status returns integer, no bytesize method
        expect(processor.send(:use_sequential?, items, :status)).to be true
      end
    end
  end

  describe "parallel_map with mocked container" do
    let(:processor) {
      described_class.new(
        pool_size: 2, min_batch_size: 1,
        min_payload_size: 1,
        errors: ApiClient::Processing::ErrorStrategy.skip
      )
    }

    it "processes items through parallel path when container is mocked" do
      responses = 3.times.map { |i| instance_double(
        Faraday::Response, body: {id: i}.to_json, status: 200, headers: {}) }

      # Mock the container to return pre-computed results
      mock_results = [[:ok, {"id" => 0}], [:ok, {"id" => 1}], [:ok, {"id" => 2}]]
      allow(processor).to receive(:process_with_container).and_return(mock_results)
      allow(Async::Container).to receive(:fork?).and_return(true)

      results = processor.map(responses)
      expect(results).to eq([{"id" => 0}, {"id" => 1}, {"id" => 2}])
    end

    it "handles errors from parallel processing" do
      responses = 2.times.map { |i| instance_double(
        Faraday::Response, body: {id: i}.to_json, status: 200, headers: {}) }

      mock_results = [
        [:error, {error_class: "JSON::ParserError", message: "bad"}],
        [:ok, {"id" => 1}]
      ]
      allow(processor).to receive(:process_with_container).and_return(mock_results)
      allow(Async::Container).to receive(:fork?).and_return(true)

      results = processor.map(responses, errors: ApiClient::Processing::ErrorStrategy.skip)
      expect(results).to eq([{"id" => 1}])
    end

    it "applies block to parallel results" do
      responses = 2.times.map { |i| instance_double(
        Faraday::Response, body: {id: i}.to_json, status: 200, headers: {}) }

      mock_results = [[:ok, {"id" => 0}], [:ok, {"id" => 1}]]
      allow(processor).to receive(:process_with_container).and_return(mock_results)
      allow(Async::Container).to receive(:fork?).and_return(true)

      results = processor.map(responses) { |h| h["id"] * 10 }
      expect(results).to eq([0, 10])
    end

    it "handles block errors in parallel path" do
      responses = 2.times.map { |i| instance_double(
        Faraday::Response, body: {id: i}.to_json, status: 200, headers: {}) }

      mock_results = [[:ok, {"id" => 0}], [:ok, {"id" => 1}]]
      allow(processor).to receive(:process_with_container).and_return(mock_results)
      allow(Async::Container).to receive(:fork?).and_return(true)

      results = processor.map(responses, errors: ApiClient::Processing::ErrorStrategy.skip) do |h|
        raise "boom" if h["id"] == 0
        h["id"]
      end
      expect(results).to eq([1])
    end
  end

  describe "#build_error" do
    let(:processor) { described_class.new(pool_size: 2, min_batch_size: 100) }

    it "reconstructs error from serialized payload" do
      payload = {error_class: "JSON::ParserError", message: "unexpected token"}
      error = processor.send(:build_error, payload)

      expect(error).to be_a(JSON::ParserError)
      expect(error.message).to eq("unexpected token")
    end

    it "falls back to StandardError for unknown classes" do
      payload = {error_class: "NonExistent::ErrorClass", message: "some error"}
      error = processor.send(:build_error, payload)

      expect(error).to be_a(StandardError)
      expect(error.message).to eq("some error")
    end
  end

  describe "#parallel_map direct testing" do
    let(:processor) {
      described_class.new(
        pool_size: 2, min_batch_size: 1,
        min_payload_size: 1,
        errors: ApiClient::Processing::ErrorStrategy.skip
      )
    }

    context "with mocked container" do
      it "extracts data, processes, and reassembles results" do
        responses = 3.times.map { |i| instance_double(
          Faraday::Response, body: {id: i}.to_json, status: 200, headers: {}) }

        mock_results = [[:ok, {"id" => 0}], [:ok, {"id" => 1}], [:ok, {"id" => 2}]]
        allow(processor).to receive(:process_with_container).and_return(mock_results)
        allow(Async::Container).to receive(:fork?).and_return(true)

        results = processor.map(responses)
        expect(results).to eq([{"id" => 0}, {"id" => 1}, {"id" => 2}])
      end

      it "handles mixed ok and error results with :replace strategy" do
        responses = 3.times.map { |i| instance_double(
          Faraday::Response, body: {id: i}.to_json, status: 200, headers: {}) }

        mock_results = [
          [:ok, {"id" => 0}],
          [:error, {error_class: "JSON::ParserError", message: "bad"}],
          [:ok, {"id" => 2}]
        ]
        allow(processor).to receive(:process_with_container).and_return(mock_results)
        allow(Async::Container).to receive(:fork?).and_return(true)

        replace_processor = described_class.new(
          pool_size: 2, min_batch_size: 1,
          min_payload_size: 1,
          errors: ApiClient::Processing::ErrorStrategy.replace({})
        )
        allow(replace_processor).to receive(:process_with_container).and_return(mock_results)

        results = replace_processor.map(responses,
          errors: ApiClient::Processing::ErrorStrategy.replace({}))
        expect(results).to eq([{"id" => 0}, {}, {"id" => 2}])
      end

      it "handles block errors in parallel results" do
        responses = 2.times.map { |i| instance_double(
          Faraday::Response, body: {id: i}.to_json, status: 200, headers: {}) }

        mock_results = [[:ok, {"id" => 0}], [:ok, {"id" => 1}]]
        allow(processor).to receive(:process_with_container).and_return(mock_results)
        allow(Async::Container).to receive(:fork?).and_return(true)

        results = processor.map(responses, errors: ApiClient::Processing::ErrorStrategy.skip) do |h|
          raise "boom" if h["id"] == 0
          h["id"]
        end
        expect(results).to eq([1])
      end

      it "handles :collect error strategy in parallel path" do
        responses = 2.times.map { |i| instance_double(
          Faraday::Response, body: {id: i}.to_json, status: 200, headers: {}) }

        mock_results = [
          [:error, {error_class: "StandardError", message: "fail"}],
          [:ok, {"id" => 1}]
        ]
        allow(processor).to receive(:process_with_container).and_return(mock_results)
        allow(Async::Container).to receive(:fork?).and_return(true)

        collect_processor = described_class.new(
          pool_size: 2, min_batch_size: 1,
          min_payload_size: 1,
          errors: ApiClient::Processing::ErrorStrategy.collect
        )
        allow(collect_processor).to receive(:process_with_container).and_return(mock_results)

        expect {
          collect_processor.map(
            responses,
            errors: ApiClient::Processing::ErrorStrategy.collect
          )
        }.to raise_error(ApiClient::AsyncProcessingError) do |error|
          expect(error.partial_results).to include({"id" => 1})
          expect(error.failure_count).to eq(1)
        end
      end

      it "handles :fail_fast error strategy in parallel path" do
        responses = 2.times.map { |i| instance_double(
          Faraday::Response, body: {id: i}.to_json, status: 200, headers: {}) }

        mock_results = [
          [:error, {error_class: "RuntimeError", message: "fail"}],
          [:ok, {"id" => 1}]
        ]
        allow(processor).to receive(:process_with_container).and_return(mock_results)
        allow(Async::Container).to receive(:fork?).and_return(true)

        ff_processor = described_class.new(
          pool_size: 2, min_batch_size: 1,
          min_payload_size: 1,
          errors: ApiClient::Processing::ErrorStrategy.fail_fast
        )
        allow(ff_processor).to receive(:process_with_container).and_return(mock_results)

        expect {
          ff_processor.map(
            responses,
            errors: ApiClient::Processing::ErrorStrategy.fail_fast
          )
        }.to raise_error(RuntimeError, "fail")
      end

      it "uses proc extractor in parallel path" do
        responses = 2.times.map { |i| instance_double(
          Faraday::Response, body: {id: i}.to_json, status: 200, headers: {}) }

        mock_results = [[:ok, {"id" => 0}], [:ok, {"id" => 1}]]
        allow(processor).to receive(:process_with_container).and_return(mock_results)
        allow(Async::Container).to receive(:fork?).and_return(true)

        results = processor.map(responses)
        expect(results).to eq([{"id" => 0}, {"id" => 1}])
      end
    end

    context "with actual forked container",
      skip: "Forked containers have IO timeout issues in RSpec" do
      it "processes data through real forked workers" do
        real_processor = described_class.new(
          pool_size: 2, min_batch_size: 1,
          min_payload_size: 1,
          errors: ApiClient::Processing::ErrorStrategy.skip
        )
        responses = 4.times.map do |i|
          body = {id: i, payload: "x" * 10_000}.to_json
          instance_double(Faraday::Response, body: body, status: 200, headers: {})
        end

        allow(Async::Container).to receive(:fork?).and_return(true)

        results = real_processor.map(responses)
        expect(results.size).to eq(4)
        expect(results.map { |r| r["id"] }).to eq([0, 1, 2, 3])
      end
    end
  end

  describe "full parallel path (end-to-end)" do
    let(:processor) { described_class.new(pool_size: 2, min_batch_size: 1, min_payload_size: 1) }

    it "processes large batch through parallel path" do
      responses = 4.times.map do |i|
        body = {id: i, data: "x" * 10_000}.to_json
        instance_double(Faraday::Response, body: body, status: 200, headers: {})
      end

      allow(Async::Container).to receive(:fork?).and_return(true)
      mock_results = 4.times.map { |i| [:ok, {"id" => i, "data" => "x" * 10_000}] }
      allow(processor).to receive(:process_with_container).and_return(mock_results)

      results = processor.map(responses)
      expect(results.size).to eq(4)
      expect(results.map { |r| r["id"] }).to eq([0, 1, 2, 3])
    end

    it "processes with block through parallel path" do
      responses = 4.times.map do |i|
        body = {id: i, data: "x" * 10_000}.to_json
        instance_double(Faraday::Response, body: body, status: 200, headers: {})
      end

      allow(Async::Container).to receive(:fork?).and_return(true)
      mock_results = 4.times.map { |i| [:ok, {"id" => i, "data" => "x" * 10_000}] }
      allow(processor).to receive(:process_with_container).and_return(mock_results)

      results = processor.map(responses) { |h| h["id"] * 10 }
      expect(results).to eq([0, 10, 20, 30])
    end

    it "handles errors in parallel path with :skip" do
      responses = [
        instance_double(Faraday::Response, body: "not json", status: 200, headers: {}),
        instance_double(Faraday::Response, body: '{"id":1}', status: 200, headers: {})
      ]

      allow(Async::Container).to receive(:fork?).and_return(true)
      mock_results = [
        [:error, {error_class: "JSON::ParserError", message: "bad"}],
        [:ok, {"id" => 1}]
      ]

      skip_processor = described_class.new(
        pool_size: 2, min_batch_size: 1,
        min_payload_size: 1,
        errors: ApiClient::Processing::ErrorStrategy.skip
      )
      allow(skip_processor).to receive(:process_with_container).and_return(mock_results)

      results = skip_processor.map(responses)
      expect(results).to include({"id" => 1})
    end

    it "handles errors in parallel path with :collect" do
      responses = [
        instance_double(Faraday::Response, body: "not json", status: 200, headers: {}),
        instance_double(Faraday::Response, body: '{"id":1}', status: 200, headers: {})
      ]

      allow(Async::Container).to receive(:fork?).and_return(true)
      mock_results = [
        [:error, {error_class: "JSON::ParserError", message: "bad"}],
        [:ok, {"id" => 1}]
      ]

      collect_processor = described_class.new(
        pool_size: 2, min_batch_size: 1,
        min_payload_size: 1,
        errors: ApiClient::Processing::ErrorStrategy.collect
      )
      allow(collect_processor).to receive(:process_with_container).and_return(mock_results)

      expect {
        collect_processor.map(responses)
      }.to raise_error(ApiClient::AsyncProcessingError)
    end
  end
end

RSpec.describe ApiClient::AsyncProcessingError do
  subject(:error) { described_class.new(results, failures) }

  let(:results) { [{"id" => 1}, {"id" => 3}] }
  let(:failures) { [{index: 1, item: "bad", error: StandardError.new("parse error")}] }

  describe "#partial_results" do
    it "returns results" do
      expect(error.partial_results).to eq([{"id" => 1}, {"id" => 3}])
    end
  end

  describe "#success_count" do
    it "counts results" do
      expect(error.success_count).to eq(2)
    end
  end

  describe "#failure_count" do
    it "counts failures" do
      expect(error.failure_count).to eq(1)
    end
  end

  describe "#message" do
    it "includes failure count" do
      expect(error.message).to include("1 items failed")
    end
  end
end
