require "spec_helper"
require "api_client/processing/processing_context"
require "api_client/processing/error_strategy"
require "api_client/error"

RSpec.describe ApiClient::Processing::ProcessingContext do
  let(:skip_strategy) { ApiClient::Processing::ErrorStrategy.skip }
  let(:collect_strategy) { ApiClient::Processing::ErrorStrategy.collect }
  let(:replace_strategy) { ApiClient::Processing::ErrorStrategy.replace("fallback") }
  let(:fail_fast_strategy) { ApiClient::Processing::ErrorStrategy.fail_fast }

  describe ".indexed" do
    subject(:context) { described_class.indexed(size: 5, errors: skip_strategy) }

    it "creates pre-allocated results array" do
      expect(context.results.size).to eq(5)
      expect(context.results).to all(be_nil)
    end

    it "creates empty error_list" do
      expect(context.error_list).to eq([])
    end

    it "stores error strategy" do
      expect(context.errors).to eq(skip_strategy)
    end

    it "marks as indexed" do
      expect(context.indexed).to be true
    end
  end

  describe ".sequential" do
    subject(:context) { described_class.sequential(errors: skip_strategy) }

    it "creates empty results array" do
      expect(context.results).to eq([])
    end

    it "creates empty error_list" do
      expect(context.error_list).to eq([])
    end

    it "marks as not indexed" do
      expect(context.indexed).to be false
    end
  end

  describe "#store_result" do
    subject(:context) { described_class.indexed(size: 3, errors: skip_strategy) }

    it "stores value at index" do
      context.store_result(1, "value")
      expect(context.results[1]).to eq("value")
    end
  end

  describe "#append_result" do
    subject(:context) { described_class.sequential(errors: skip_strategy) }

    it "appends value to results" do
      context.append_result("a")
      context.append_result("b")
      expect(context.results).to eq(["a", "b"])
    end
  end

  describe "#record_error" do
    subject(:context) { described_class.indexed(size: 3, errors: skip_strategy) }

    let(:item) { {id: 1} }
    let(:error) { StandardError.new("boom") }

    it "adds error info to error_list" do
      context.record_error(1, item, error)
      expect(context.error_list.size).to eq(1)
      expect(context.error_list.first).to include(index: 1, item: item, error: error)
    end

    it "returns error info hash" do
      result = context.record_error(1, item, error)
      expect(result).to eq({index: 1, item: item, error: error})
    end
  end

  describe "#errors?" do
    subject(:context) { described_class.indexed(size: 3, errors: skip_strategy) }

    it "returns false when no errors" do
      expect(context.errors?).to be false
    end

    it "returns true when errors present" do
      context.record_error(0, {}, StandardError.new)
      expect(context.errors?).to be true
    end
  end

  describe "#strategy" do
    it "returns strategy symbol" do
      context = described_class.indexed(size: 1, errors: skip_strategy)
      expect(context.strategy).to eq(:skip)
    end
  end

  describe "#fallback" do
    it "returns nil for non-replace strategies" do
      context = described_class.indexed(size: 1, errors: skip_strategy)
      expect(context.fallback).to be_nil
    end

    it "returns fallback value for replace strategy" do
      context = described_class.indexed(size: 1, errors: replace_strategy)
      expect(context.fallback).to eq("fallback")
    end
  end

  describe "#raises_on_error?" do
    it "returns true for fail_fast" do
      context = described_class.indexed(size: 1, errors: fail_fast_strategy)
      expect(context.raises_on_error?).to be true
    end

    it "returns true for collect" do
      context = described_class.indexed(size: 1, errors: collect_strategy)
      expect(context.raises_on_error?).to be true
    end

    it "returns false for skip" do
      context = described_class.indexed(size: 1, errors: skip_strategy)
      expect(context.raises_on_error?).to be false
    end

    it "returns false for replace" do
      context = described_class.indexed(size: 1, errors: replace_strategy)
      expect(context.raises_on_error?).to be false
    end
  end

  describe "#error_count" do
    subject(:context) { described_class.indexed(size: 3, errors: skip_strategy) }

    it "returns count of errors" do
      context.record_error(0, {}, StandardError.new)
      context.record_error(2, {}, StandardError.new)
      expect(context.error_count).to eq(2)
    end
  end

  describe "#success_count" do
    subject(:context) { described_class.indexed(size: 5, errors: skip_strategy) }

    it "returns count of non-nil results" do
      context.store_result(0, "a")
      context.store_result(2, "b")
      context.store_result(4, "c")
      expect(context.success_count).to eq(3)
    end
  end

  describe "#finalize" do
    context "with no errors" do
      subject(:context) { described_class.indexed(size: 3, errors: skip_strategy) }

      it "returns compacted results" do
        context.store_result(0, "a")
        context.store_result(2, "c")
        result = context.finalize(error_class: ApiClient::RactorProcessingError)
        expect(result).to eq(["a", "c"])
      end
    end

    context "with :skip strategy" do
      subject(:context) { described_class.indexed(size: 3, errors: skip_strategy) }

      it "returns compacted results ignoring errors" do
        context.store_result(0, "a")
        context.record_error(1, {}, StandardError.new)
        context.store_result(2, "c")

        result = context.finalize(error_class: ApiClient::RactorProcessingError)
        expect(result).to eq(["a", "c"])
      end
    end

    context "with :fail_fast strategy" do
      subject(:context) { described_class.indexed(size: 3, errors: fail_fast_strategy) }

      it "returns compacted results" do
        context.store_result(0, "a")
        context.record_error(1, {}, StandardError.new)

        result = context.finalize(error_class: ApiClient::RactorProcessingError)
        expect(result).to eq(["a"])
      end
    end

    context "with :collect strategy" do
      subject(:context) { described_class.indexed(size: 3, errors: collect_strategy) }

      it "raises error class with partial results" do
        context.store_result(0, "a")
        context.record_error(1, {id: 1}, StandardError.new("boom"))
        context.store_result(2, "c")

        expect {
          context.finalize(error_class: ApiClient::RactorProcessingError)
        }.to raise_error(ApiClient::RactorProcessingError) do |error|
          expect(error.partial_results).to eq(["a", "c"])
          expect(error.failure_count).to eq(1)
        end
      end
    end

    context "with :replace strategy" do
      subject(:context) { described_class.indexed(size: 3, errors: replace_strategy) }

      it "returns results without compacting (preserves fallbacks)" do
        context.store_result(0, "a")
        context.store_result(1, "fallback")
        context.record_error(1, {}, StandardError.new)
        context.store_result(2, "c")

        result = context.finalize(error_class: ApiClient::RactorProcessingError)
        expect(result).to eq(["a", "fallback", "c"])
      end
    end
  end
end
