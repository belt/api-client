require "spec_helper"
require "api_client"

RSpec.describe "ErrorStrategy sentinel behavior" do
  let(:skipped) { ApiClient::Processing::SKIPPED }

  describe "SKIPPED sentinel" do
    it "is frozen" do
      expect(skipped).to be_frozen
    end

    it "is distinct from nil" do
      expect(skipped).not_to be_nil
    end

    it "is identity-comparable" do
      expect(skipped.equal?(skipped)).to be true
      expect(skipped.equal?(Object.new)).to be false
    end
  end

  describe "ErrorStrategy#apply with sentinel" do
    it "skip strategy does not add to results" do
      strategy = ApiClient::Processing::ErrorStrategy.skip
      results = []
      strategy.apply(RuntimeError.new("err"), results)
      expect(results).to be_empty
    end

    it "collect strategy appends SKIPPED sentinel" do
      strategy = ApiClient::Processing::ErrorStrategy.collect
      results = []
      strategy.apply(RuntimeError.new("err"), results)
      expect(results.size).to eq(1)
      expect(results.first.equal?(skipped)).to be true
    end

    it "replace strategy appends fallback value" do
      strategy = ApiClient::Processing::ErrorStrategy.replace("default")
      results = []
      strategy.apply(RuntimeError.new("err"), results)
      expect(results).to eq(["default"])
    end

    it "fail_fast strategy raises immediately" do
      strategy = ApiClient::Processing::ErrorStrategy.fail_fast
      expect {
        strategy.apply(RuntimeError.new("boom"), [])
      }.to raise_error(RuntimeError, "boom")
    end
  end

  describe "ErrorStrategy#apply_indexed with sentinel" do
    it "collect strategy sets SKIPPED at index" do
      strategy = ApiClient::Processing::ErrorStrategy.collect
      results = Array.new(3)
      strategy.apply_indexed(1, RuntimeError.new("err"), results)
      expect(results[1].equal?(skipped)).to be true
      expect(results[0]).to be_nil
    end

    it "skip strategy sets SKIPPED at index" do
      strategy = ApiClient::Processing::ErrorStrategy.skip
      results = Array.new(3)
      strategy.apply_indexed(2, RuntimeError.new("err"), results)
      expect(results[2].equal?(skipped)).to be true
    end

    it "replace strategy sets fallback at index" do
      strategy = ApiClient::Processing::ErrorStrategy.replace(42)
      results = Array.new(3)
      strategy.apply_indexed(0, RuntimeError.new("err"), results)
      expect(results[0]).to eq(42)
    end
  end

  describe "ErrorStrategy#finalize with sentinel" do
    it "removes SKIPPED from results" do
      strategy = ApiClient::Processing::ErrorStrategy.skip
      results = ["a", skipped, "b", skipped, "c"]
      cleaned = strategy.finalize(results, [], StandardError)
      expect(cleaned).to eq(["a", "b", "c"])
    end

    it "preserves nil values in results (nil is not SKIPPED)" do
      strategy = ApiClient::Processing::ErrorStrategy.skip
      results = ["a", nil, "b"]
      cleaned = strategy.finalize(results, [], StandardError)
      expect(cleaned).to eq(["a", nil, "b"])
    end

    it "collect strategy raises with cleaned partial results" do
      strategy = ApiClient::Processing::ErrorStrategy.collect
      results = ["a", skipped, "b"]
      errors = [{index: 1, error: RuntimeError.new("err")}]

      expect {
        strategy.finalize(results, errors, ApiClient::ConcurrentProcessingError)
      }.to raise_error(ApiClient::ConcurrentProcessingError) { |e|
        expect(e.partial_results).to eq(["a", "b"])
      }
    end

    it "replace strategy removes SKIPPED but keeps fallback values" do
      strategy = ApiClient::Processing::ErrorStrategy.replace("fallback")
      results = ["a", "fallback", "b"]
      errors = [{index: 1, error: RuntimeError.new("err")}]
      cleaned = strategy.finalize(results, errors, StandardError)
      expect(cleaned).to eq(["a", "fallback", "b"])
    end
  end

  describe "ProcessingContext#finalize with sentinel" do
    it "removes SKIPPED and nil from results" do
      ctx = ApiClient::Processing::ProcessingContext.indexed(
        size: 5,
        errors: ApiClient::Processing::ErrorStrategy.skip
      )
      ctx.store_result(0, "a")
      # index 1 left nil (pre-allocated)
      ctx.store_result(2, skipped)
      ctx.store_result(3, "b")
      ctx.store_result(4, skipped)

      result = ctx.finalize(error_class: ApiClient::ConcurrentProcessingError)
      expect(result).to eq(["a", "b"])
    end

    it "success_count excludes SKIPPED and nil" do
      ctx = ApiClient::Processing::ProcessingContext.indexed(
        size: 4,
        errors: ApiClient::Processing::ErrorStrategy.skip
      )
      ctx.store_result(0, "a")
      ctx.store_result(1, nil)
      ctx.store_result(2, skipped)
      ctx.store_result(3, "b")

      expect(ctx.success_count).to eq(2)
    end
  end
end
