require "spec_helper"
require "api_client"
require "faraday"

# Failure strategy specs verify multi-step error handling pipelines.
# rubocop:disable RSpec/ExampleLength, RSpec/MultipleExpectations, RSpec/MultipleMemoizedHelpers
RSpec.describe ApiClient::Streaming::FailureStrategy do
  describe ".from" do
    it "builds fail_fast from symbol" do
      strategy = described_class.from(:fail_fast)
      expect(strategy.strategy).to eq(:fail_fast)
      expect(strategy.handler).to be_nil
    end

    it "builds skip from symbol" do
      strategy = described_class.from(:skip)
      expect(strategy.strategy).to eq(:skip)
    end

    it "builds collect from symbol" do
      strategy = described_class.from(:collect)
      expect(strategy.strategy).to eq(:collect)
    end

    it "builds callback from Proc" do
      proc = ->(source, request) { "fallback" }
      strategy = described_class.from(proc)
      expect(strategy.strategy).to eq(:callback)
      expect(strategy.handler).to eq(proc)
    end

    it "defaults to fail_fast for unknown symbols" do
      strategy = described_class.from(:unknown)
      expect(strategy.strategy).to eq(:fail_fast)
    end
  end

  describe ".default" do
    it "returns fail_fast" do
      expect(described_class.default.strategy).to eq(:fail_fast)
    end
  end

  describe "#apply" do
    let(:results) { Array.new(3) }
    let(:errors) { [] }
    let(:failure) { {kind: :response, index: 1, status: 0} }
    let(:source) { instance_double(Faraday::Response, status: 0) }
    let(:request) { {method: :get, url: "/test"} }
    let(:error_to_raise) { RuntimeError.new("fan out failed") }

    context "with :fail_fast strategy" do
      let(:strategy) { described_class.fail_fast }

      it "raises the provided error" do
        expect {
          strategy.apply(
            index: 1, source: source, request: request,
            results: results, errors: errors, failure: failure,
            raise_error: error_to_raise, preserve_order: true
          )
        }.to raise_error(RuntimeError, "fan out failed")
      end

      it "records the failure before raising" do
        begin
          strategy.apply(
            index: 1, source: source, request: request,
            results: results, errors: errors, failure: failure,
            raise_error: error_to_raise, preserve_order: true
          )
        rescue
          nil
        end

        expect(errors.size).to eq(1)
      end
    end

    context "with :skip strategy" do
      let(:strategy) { described_class.skip }

      it "does not store anything in results" do
        strategy.apply(
          index: 1, source: source, request: request,
          results: results, errors: errors, failure: failure,
          raise_error: error_to_raise, preserve_order: true
        )

        expect(results[1]).to be_nil
      end

      it "records the failure" do
        strategy.apply(
          index: 1, source: source, request: request,
          results: results, errors: errors, failure: failure,
          raise_error: error_to_raise, preserve_order: true
        )

        expect(errors.size).to eq(1)
      end
    end

    context "with :collect strategy" do
      let(:strategy) { described_class.collect }

      it "stores the source in results at the correct index" do
        strategy.apply(
          index: 1, source: source, request: request,
          results: results, errors: errors, failure: failure,
          raise_error: error_to_raise, preserve_order: true
        )

        expect(results[1]).to eq(source)
      end

      it "appends to results in arrival order" do
        arrival_results = []
        strategy.apply(
          index: 1, source: source, request: request,
          results: arrival_results, errors: errors, failure: failure,
          raise_error: error_to_raise, preserve_order: false
        )

        expect(arrival_results).to eq([source])
      end
    end

    context "with :callback strategy" do
      it "calls the handler with source and request" do
        called_with = nil
        handler = ->(src, req) {
          called_with = {source: src, request: req}
          instance_double(Faraday::Response, status: 999, body: "fallback")
        }
        strategy = described_class.callback(handler)

        strategy.apply(
          index: 1, source: source, request: request,
          results: results, errors: errors, failure: failure,
          raise_error: error_to_raise, preserve_order: true
        )

        expect(called_with[:source]).to eq(source)
        expect(called_with[:request]).to eq(request)
      end

      it "stores the fallback value" do
        fallback = instance_double(Faraday::Response, status: 999)
        strategy = described_class.callback(->(_s, _r) { fallback })

        strategy.apply(
          index: 1, source: source, request: request,
          results: results, errors: errors, failure: failure,
          raise_error: error_to_raise, preserve_order: true
        )

        expect(results[1]).to eq(fallback)
      end

      it "skips nil fallback" do
        strategy = described_class.callback(->(_s, _r) {})

        strategy.apply(
          index: 1, source: source, request: request,
          results: results, errors: errors, failure: failure,
          raise_error: error_to_raise, preserve_order: true
        )

        expect(results[1]).to be_nil
      end
    end

    context "with streaming callback" do
      it "yields to block after storing result" do
        strategy = described_class.collect
        yielded = nil

        strategy.apply(
          index: 1, source: source, request: request,
          results: results, errors: errors, failure: failure,
          raise_error: error_to_raise, preserve_order: true
        ) { |value, idx| yielded = [value, idx] }

        expect(yielded).to eq([source, 1])
      end
    end
  end

  describe "#finalize" do
    context "with no errors" do
      it "returns results as-is for preserve order" do
        strategy = described_class.fail_fast
        results = ["a", nil, "c"]
        expect(strategy.finalize(results, [], true)).to eq(["a", nil, "c"])
      end

      it "compacts results for arrival order" do
        strategy = described_class.fail_fast
        results = ["a", nil, "c"]
        expect(strategy.finalize(results, [], false)).to eq(["a", "c"])
      end
    end

    context "with :collect and errors" do
      it "raises FanOutError" do
        strategy = described_class.collect
        errors = [{kind: :response, status: 0}]

        expect {
          strategy.finalize(["a", nil], errors, true)
        }.to raise_error(ApiClient::FanOutError)
      end
    end

    context "with :skip and errors" do
      it "returns results without raising" do
        strategy = described_class.skip
        errors = [{kind: :response, status: 0}]

        result = strategy.finalize(["a", nil], errors, true)
        expect(result).to eq(["a", nil])
      end
    end

    context "with :raw cleanup" do
      it "removes :raw references from error entries" do
        strategy = described_class.skip
        error = RuntimeError.new("test")
        errors = [{kind: :exception, raw: error, message: "test"}]

        strategy.finalize([], errors, true)
        expect(errors.first).not_to have_key(:raw)
      end
    end
  end

  describe "immutability" do
    it "is frozen (Data.define)" do
      strategy = described_class.fail_fast
      expect(strategy).to be_frozen
    end
  end
end
# rubocop:enable RSpec/ExampleLength, RSpec/MultipleExpectations, RSpec/MultipleMemoizedHelpers
