require "spec_helper"
require "api_client"

RSpec.describe "FailureStrategy fuzzing", :fuzz do
  describe "FailureStrategy.from with random inputs" do
    it "returns a valid strategy for all known symbols" do
      %i[fail_fast skip collect].each do |sym|
        strategy = ApiClient::Streaming::FailureStrategy.from(sym)
        expect(strategy.strategy).to eq(sym)
      end
    end

    it "returns fail_fast for unknown symbols" do
      property_of {
        sized(10) { string(:alpha) }.to_sym
      }.check(10) do |sym|
        next if %i[fail_fast skip collect].include?(sym)
        strategy = ApiClient::Streaming::FailureStrategy.from(sym)
        expect(strategy.strategy).to eq(:fail_fast)
      end
    end

    it "returns callback strategy for Proc" do
      strategy = ApiClient::Streaming::FailureStrategy.from(->(_s, _r) { nil })
      expect(strategy.strategy).to eq(:callback)
    end
  end

  describe "FailureStrategy#finalize" do
    it "compacts nil from preserve-order results" do
      strategy = ApiClient::Streaming::FailureStrategy.skip
      results = ["a", nil, "b", nil, "c"]
      cleaned = strategy.finalize(results, [], true)
      # preserve_order=true returns results as-is (nils from pre-allocated slots)
      expect(cleaned).to eq(["a", nil, "b", nil, "c"])
    end

    it "compacts nil from arrival-order results" do
      strategy = ApiClient::Streaming::FailureStrategy.skip
      results = ["a", nil, "b"]
      cleaned = strategy.finalize(results, [], false)
      expect(cleaned).to eq(["a", "b"])
    end

    it "collect strategy raises FanOutError when errors present" do
      strategy = ApiClient::Streaming::FailureStrategy.collect
      results = ["a", nil, "b"]
      errors = [{index: 1, error_class: "RuntimeError", message: "err"}]

      expect {
        strategy.finalize(results, errors, false)
      }.to raise_error(ApiClient::FanOutError)
    end

    it "clears :raw from error hashes to prevent memory anchoring" do
      strategy = ApiClient::Streaming::FailureStrategy.skip
      error_obj = RuntimeError.new("test")
      errors = [{index: 0, raw: error_obj, message: "test"}]

      strategy.finalize([], errors, true)
      expect(errors.first).not_to have_key(:raw)
    end
  end

  describe "FailureStrategy#apply with random strategies" do
    let(:base_args) do
      {
        index: 0,
        source: RuntimeError.new("err"),
        request: {method: :get, path: "/test"},
        results: [],
        errors: [],
        failure: {index: 0, message: "err"},
        preserve_order: false
      }
    end

    it "fail_fast always raises" do
      strategy = ApiClient::Streaming::FailureStrategy.fail_fast
      expect {
        strategy.apply(**base_args, raise_error: RuntimeError.new("boom"))
      }.to raise_error(RuntimeError, "boom")
    end

    it "skip does not store anything in results" do
      strategy = ApiClient::Streaming::FailureStrategy.skip
      results = []
      strategy.apply(**base_args.merge(results: results), raise_error: RuntimeError.new("x"))
      expect(results).to be_empty
    end

    it "collect stores source in results" do
      strategy = ApiClient::Streaming::FailureStrategy.collect
      results = []
      source = RuntimeError.new("err")
      strategy.apply(**base_args.merge(results: results, source: source), raise_error: source)
      expect(results.size).to eq(1)
    end

    it "callback invokes handler and stores non-nil result" do
      handler = ->(_source, _req) { "fallback_value" }
      strategy = ApiClient::Streaming::FailureStrategy.callback(handler)
      results = []
      strategy.apply(**base_args.merge(results: results), raise_error: RuntimeError.new("x"))
      expect(results).to eq(["fallback_value"])
    end

    it "callback does not store nil handler result" do
      handler = ->(_source, _req) { nil }
      strategy = ApiClient::Streaming::FailureStrategy.callback(handler)
      results = []
      strategy.apply(**base_args.merge(results: results), raise_error: RuntimeError.new("x"))
      expect(results).to be_empty
    end
  end
end
