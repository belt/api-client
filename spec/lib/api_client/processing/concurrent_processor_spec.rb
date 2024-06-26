require "spec_helper"
require "api_client"
require "api_client/processing/concurrent_processor"
require "faraday"

RSpec.describe ApiClient::Processing::ConcurrentProcessor do
  subject(:processor) {
    described_class.new(
      pool_size: 2, min_batch_size: 1, errors: ApiClient::Processing::ErrorStrategy.skip
    )
  }

  describe ".available?" do
    it "returns true when concurrent-ruby is available" do
      expect(described_class.available?).to be true
    end
  end

  describe "#initialize" do
    it "uses configuration defaults" do
      ApiClient.configure do |config|
        config.processor_config.concurrent_processor_pool_size = 4
        config.processor_config.concurrent_processor_min_batch_size = 5
      end

      default_processor = described_class.new
      expect(default_processor.pool_size).to eq(4)
      expect(default_processor.min_batch_size).to eq(5)
      expect(default_processor.default_error_strategy.strategy).to eq(:fail_fast)
    end

    it "accepts custom options" do
      custom = described_class.new(
        pool_size: 8, min_batch_size: 10, errors: ApiClient::Processing::ErrorStrategy.fail_fast
      )
      expect(custom.pool_size).to eq(8)
      expect(custom.min_batch_size).to eq(10)
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
      large_batch_processor = described_class.new(min_batch_size: 10)
      results = large_batch_processor.map(small_responses)
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
      it "raises ConcurrentProcessingError with partial results" do
        expect {
          processor.map(bad_responses, errors: ApiClient::Processing::ErrorStrategy.collect)
        }.to raise_error(ApiClient::ConcurrentProcessingError) do |error|
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

    it "instruments concurrent_processor_start" do
      events = []
      subscriber = ApiClient::Hooks.subscribe(:concurrent_processor_start) do |*args|
        events << ActiveSupport::Notifications::Event.new(*args)
      end

      processor.map(responses)

      expect(events.size).to eq(1)
      expect(events.first.payload).to include(operation: :map, count: 3)
    ensure
      ApiClient::Hooks.unsubscribe(subscriber)
    end

    it "instruments concurrent_processor_complete" do
      events = []
      subscriber = ApiClient::Hooks.subscribe(:concurrent_processor_complete) do |*args|
        events << ActiveSupport::Notifications::Event.new(*args)
      end

      processor.map(responses)

      expect(events.size).to eq(1)
      expect(events.first.payload).to include(operation: :map, input_count: 3, output_count: 3)
    ensure
      ApiClient::Hooks.unsubscribe(subscriber)
    end

    it "instruments concurrent_processor_error" do
      bad = [instance_double(Faraday::Response, body: "bad", status: 200, headers: {})]
      events = []
      subscriber = ApiClient::Hooks.subscribe(:concurrent_processor_error) do |*args|
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

RSpec.describe ApiClient::ConcurrentProcessingError do
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
