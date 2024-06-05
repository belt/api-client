require "spec_helper"
require "api_client"

RSpec.describe ApiClient::Processing::BaseProcessor do
  # Use a concrete implementation for testing shared behavior
  let(:processor_class) do
    Class.new do
      include ApiClient::Processing::BaseProcessor
      include ApiClient::Processing::ProcessorInstrumentation

      attr_reader :default_error_strategy

      def initialize(errors: ApiClient::Processing::ErrorStrategy.skip)
        @default_error_strategy = errors
      end

      def parallel_map(items, recipe:, errors:, &block)
        sequential_map(items, recipe: recipe, errors: errors, &block)
      end

      def use_sequential?(_items, _extract)
        true
      end

      def processing_error_class
        ApiClient::RactorProcessingError
      end

      def instrument_event_prefix
        :test_processor
      end
    end
  end

  let(:processor) { processor_class.new }

  describe "#resolve_extractor" do
    it "resolves :body extractor" do
      response = double(body: "hello")
      extractor = processor.resolve_extractor(:body)
      expect(extractor.call(response)).to eq("hello")
    end

    it "resolves :status extractor" do
      response = double(status: 404)
      extractor = processor.resolve_extractor(:status)
      expect(extractor.call(response)).to eq(404)
    end

    it "resolves :headers extractor" do
      response = double(headers: double(to_h: {"Content-Type" => "application/json"}))
      extractor = processor.resolve_extractor(:headers)
      expect(extractor.call(response)).to eq({"Content-Type" => "application/json"})
    end

    it "resolves :identity extractor" do
      extractor = processor.resolve_extractor(:identity)
      expect(extractor.call("anything")).to eq("anything")
    end

    it "returns proc as-is" do
      custom = ->(x) { x.upcase }
      extractor = processor.resolve_extractor(custom)
      expect(extractor.call("hello")).to eq("HELLO")
    end

    it "raises for unknown symbol" do
      expect { processor.resolve_extractor(:unknown) }
        .to raise_error(ArgumentError, /Unknown extractor/)
    end

    it "raises for invalid type" do
      expect { processor.resolve_extractor(42) }
        .to raise_error(ArgumentError, /must be Symbol or Proc/)
    end
  end

  describe "#build_error" do
    it "reconstructs known error class" do
      error = processor.send(:build_error, {error_class: "ArgumentError", message: "bad arg"})
      expect(error).to be_a(ArgumentError)
      expect(error.message).to eq("bad arg")
    end

    it "falls back to StandardError for unknown class" do
      error = processor.send(:build_error, {error_class: "NonExistent::Error", message: "oops"})
      expect(error).to be_a(StandardError)
      expect(error.message).to eq("oops")
    end
  end

  describe "#map" do
    let(:responses) do
      3.times.map { |i| double(body: {id: i}.to_json, status: 200, headers: {}) }
    end

    it "returns empty array for empty input" do
      expect(processor.map([])).to eq([])
    end

    it "transforms responses with default recipe" do
      results = processor.map(responses)
      expect(results).to eq([{"id" => 0}, {"id" => 1}, {"id" => 2}])
    end

    it "applies block" do
      results = processor.map(responses) { |h| h["id"] }
      expect(results).to eq([0, 1, 2])
    end

    it "accepts recipe parameter object" do
      recipe = ApiClient::Transforms::Recipe.new(extract: :body, transform: :json)
      results = processor.map(responses, recipe: recipe)
      expect(results).to eq([{"id" => 0}, {"id" => 1}, {"id" => 2}])
    end

    it "accepts errors parameter object" do
      errors = ApiClient::Processing::ErrorStrategy.fail_fast
      results = processor.map(responses, errors: errors)
      expect(results.size).to eq(3)
    end

    it "coerces nil to empty array" do
      expect(processor.map(nil)).to eq([])
    end
  end

  describe "#sequential_map error handling" do
    let(:bad_responses) do
      [
        double(body: "not json", status: 200, headers: {}),
        double(body: '{"id":1}', status: 200, headers: {})
      ]
    end

    it "skips errors with :skip strategy" do
      results = processor.map(bad_responses, errors: ApiClient::Processing::ErrorStrategy.skip)
      expect(results).to eq([{"id" => 1}])
    end

    it "replaces errors with :replace strategy" do
      results = processor.map(bad_responses,
        errors: ApiClient::Processing::ErrorStrategy.replace({}))
      expect(results).to eq([{}, {"id" => 1}])
    end

    it "raises on first error with :fail_fast strategy" do
      expect {
        processor.map(bad_responses, errors: ApiClient::Processing::ErrorStrategy.fail_fast)
      }.to raise_error(JSON::ParserError)
    end

    it "collects errors with :collect strategy" do
      expect {
        processor.map(bad_responses, errors: ApiClient::Processing::ErrorStrategy.collect)
      }.to raise_error(ApiClient::RactorProcessingError) do |error|
        expect(error.partial_results).to include({"id" => 1})
        expect(error.failure_count).to eq(1)
      end
    end
  end

  describe "#handle_indexed_error" do
    let(:results) { Array.new(3) }
    let(:error_list) { [] }
    let(:error) { StandardError.new("boom") }

    it "raises on :fail_fast" do
      errors = ApiClient::Processing::ErrorStrategy.fail_fast
      expect {
        processor.send(
          :handle_indexed_error,
          index: 0, item: "x", error: error,
          errors: errors, results: results, error_list: error_list
        )
      }.to raise_error(StandardError, "boom")
    end

    it "sets SKIPPED sentinel on :collect" do
      errors = ApiClient::Processing::ErrorStrategy.collect
      processor.send(
        :handle_indexed_error,
        index: 1, item: "x", error: error,
        errors: errors, results: results, error_list: error_list
      )
      expect(results[1]).to equal(ApiClient::Processing::SKIPPED)
    end

    it "sets SKIPPED sentinel on :skip" do
      errors = ApiClient::Processing::ErrorStrategy.skip
      processor.send(
        :handle_indexed_error,
        index: 1, item: "x", error: error,
        errors: errors, results: results, error_list: error_list
      )
      expect(results[1]).to equal(ApiClient::Processing::SKIPPED)
    end

    it "sets fallback on :replace" do
      errors = ApiClient::Processing::ErrorStrategy.replace("fallback")
      processor.send(
        :handle_indexed_error,
        index: 1, item: "x", error: error,
        errors: errors, results: results, error_list: error_list
      )
      expect(results[1]).to eq("fallback")
    end
  end

  describe "#handle_indexed_error_result" do
    let(:results) { Array.new(3) }
    let(:error) { StandardError.new("boom") }

    it "raises on :fail_fast" do
      errors = ApiClient::Processing::ErrorStrategy.fail_fast
      expect {
        processor.send(
          :handle_indexed_error_result,
          index: 0, error: error, errors: errors, results: results
        )
      }.to raise_error(StandardError, "boom")
    end

    it "sets SKIPPED sentinel on :collect" do
      errors = ApiClient::Processing::ErrorStrategy.collect
      processor.send(
        :handle_indexed_error_result,
        index: 1, error: error, errors: errors, results: results
      )
      expect(results[1]).to equal(ApiClient::Processing::SKIPPED)
    end

    it "sets SKIPPED sentinel on :skip" do
      errors = ApiClient::Processing::ErrorStrategy.skip
      processor.send(
        :handle_indexed_error_result,
        index: 1, error: error, errors: errors, results: results
      )
      expect(results[1]).to equal(ApiClient::Processing::SKIPPED)
    end

    it "sets fallback on :replace" do
      errors = ApiClient::Processing::ErrorStrategy.replace("default")
      processor.send(
        :handle_indexed_error_result,
        index: 1, error: error, errors: errors, results: results
      )
      expect(results[1]).to eq("default")
    end
  end

  describe "#finalize_indexed_results" do
    it "preserves nil results when no errors" do
      results = ["a", nil, "c"]
      result = processor.send(
        :finalize_indexed_results,
        results: results, error_list: [],
        errors: ApiClient::Processing::ErrorStrategy.skip
      )
      expect(result).to eq(["a", nil, "c"])
    end

    it "removes SKIPPED sentinels on :fail_fast with errors" do
      results = ["a", ApiClient::Processing::SKIPPED]
      errors = ApiClient::Processing::ErrorStrategy.fail_fast
      result = processor.send(
        :finalize_indexed_results,
        results: results, error_list: [{index: 1}], errors: errors
      )
      expect(result).to eq(["a"])
    end

    it "raises on :collect with errors" do
      results = ["a", ApiClient::Processing::SKIPPED]
      errors = ApiClient::Processing::ErrorStrategy.collect
      expect {
        processor.send(
          :finalize_indexed_results,
          results: results, error_list: [{index: 1}], errors: errors
        )
      }.to raise_error(ApiClient::RactorProcessingError)
    end

    it "removes SKIPPED sentinels on :skip with errors" do
      results = ["a", ApiClient::Processing::SKIPPED, "c"]
      errors = ApiClient::Processing::ErrorStrategy.skip
      result = processor.send(
        :finalize_indexed_results,
        results: results, error_list: [{index: 1}], errors: errors
      )
      expect(result).to eq(["a", "c"])
    end

    it "preserves nils on :replace with errors" do
      results = ["a", "fallback", "c"]
      errors = ApiClient::Processing::ErrorStrategy.replace("fallback")
      result = processor.send(
        :finalize_indexed_results,
        results: results, error_list: [{index: 1}], errors: errors
      )
      expect(result).to eq(["a", "fallback", "c"])
    end
  end

  describe "#select" do
    let(:responses) do
      3.times.map { |i| double(body: {id: i, even: i.even?}.to_json, status: 200, headers: {}) }
    end

    it "returns empty for empty input" do
      expect(processor.select([]) { true }).to eq([])
    end

    it "filters based on predicate" do
      results = processor.select(responses) { |h| h["even"] }
      expect(results.size).to eq(2)
    end
  end

  describe "#reduce" do
    let(:responses) do
      3.times.map { |i| double(body: {value: i + 1}.to_json, status: 200, headers: {}) }
    end

    it "returns initial for empty input" do
      expect(processor.reduce([], 0) { |acc, _| acc }).to eq(0)
    end

    it "reduces values" do
      result = processor.reduce(responses, 0) { |acc, h| acc + h["value"] }
      expect(result).to eq(6)
    end
  end
end

RSpec.describe ApiClient::Processing::ProcessorInstrumentation do
  let(:processor_class) do
    Class.new do
      include ApiClient::Processing::BaseProcessor
      include ApiClient::Processing::ProcessorInstrumentation

      attr_reader :default_error_strategy

      def initialize
        @default_error_strategy = ApiClient::Processing::ErrorStrategy.skip
      end

      def parallel_map(items, recipe:, errors:, &block)
        sequential_map(items, recipe: recipe, errors: errors, &block)
      end

      def use_sequential?(_items, _extract)
        true
      end

      def processing_error_class
        ApiClient::ProcessingError
      end

      def instrument_event_prefix
        :test_proc
      end

      def instrument_start_metadata
        {custom: true}
      end
    end
  end

  let(:processor) { processor_class.new }

  it "instruments start with custom metadata" do
    events = []
    subscriber = ApiClient::Hooks.subscribe(:test_proc_start) do |*args|
      events << ActiveSupport::Notifications::Event.new(*args)
    end

    responses = [double(body: '{"id":1}', status: 200, headers: {})]
    processor.map(responses)

    expect(events.size).to eq(1)
    expect(events.first.payload).to include(operation: :map, count: 1, custom: true)
  ensure
    ApiClient::Hooks.unsubscribe(subscriber)
  end

  it "instruments complete" do
    events = []
    subscriber = ApiClient::Hooks.subscribe(:test_proc_complete) do |*args|
      events << ActiveSupport::Notifications::Event.new(*args)
    end

    responses = [double(body: '{"id":1}', status: 200, headers: {})]
    processor.map(responses)

    expect(events.size).to eq(1)
    expect(events.first.payload).to include(operation: :map, input_count: 1, output_count: 1)
  ensure
    ApiClient::Hooks.unsubscribe(subscriber)
  end

  it "instruments error" do
    events = []
    subscriber = ApiClient::Hooks.subscribe(:test_proc_error) do |*args|
      events << ActiveSupport::Notifications::Event.new(*args)
    end

    bad = [double(body: "not json", status: 200, headers: {})]
    processor.map(bad, errors: ApiClient::Processing::ErrorStrategy.skip)

    expect(events.size).to eq(1)
    expect(events.first.payload).to include(index: 0, strategy: :skip, will_raise: false)
  ensure
    ApiClient::Hooks.unsubscribe(subscriber)
  end
end
