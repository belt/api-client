require "spec_helper"
require "api_client"

RSpec.describe "ErrorStrategy fuzzing", :fuzz do
  let(:skipped) { ApiClient::Processing::SKIPPED }

  describe "random error patterns with skip strategy" do
    it "always removes exactly the failed items" do
      strategy = ApiClient::Processing::ErrorStrategy.skip

      property_of { array(10) { boolean } }.check(20) do |pattern|
        results = []
        error_list = []

        pattern.each_with_index do |should_fail, i|
          if should_fail
            error_list << {index: i, error: RuntimeError.new("err")}
            # skip strategy: don't add to results
          else
            results << "item_#{i}"
          end
        end

        cleaned = strategy.finalize(results, error_list, ApiClient::ConcurrentProcessingError)
        expected_count = pattern.count(false)
        expect(cleaned.size).to eq(expected_count)
      end
    end
  end

  describe "random error patterns with collect strategy" do
    it "raises with correct partial result count" do
      strategy = ApiClient::Processing::ErrorStrategy.collect

      property_of { array(10) { boolean } }.check(20) do |pattern|
        results = []
        error_list = []

        pattern.each_with_index do |should_fail, i|
          if should_fail
            error_list << {index: i, error: RuntimeError.new("err")}
            results << skipped
          else
            results << "item_#{i}"
          end
        end

        if error_list.any?
          expect {
            strategy.finalize(results, error_list, ApiClient::ConcurrentProcessingError)
          }.to raise_error(ApiClient::ConcurrentProcessingError) { |e|
            expect(e.partial_results.size).to eq(pattern.count(false))
          }
        else
          cleaned = strategy.finalize(results, error_list, ApiClient::ConcurrentProcessingError)
          expect(cleaned.size).to eq(10)
        end
      end
    end
  end

  describe "random error patterns with replace strategy" do
    it "replaces failed items with fallback" do
      fallback = {replaced: true}
      strategy = ApiClient::Processing::ErrorStrategy.replace(fallback)

      property_of { array(8) { boolean } }.check(15) do |pattern|
        results = []
        error_list = []

        pattern.each_with_index do |should_fail, i|
          if should_fail
            error_list << {index: i, error: RuntimeError.new("err")}
            results << fallback
          else
            results << "item_#{i}"
          end
        end

        cleaned = strategy.finalize(results, error_list, ApiClient::ConcurrentProcessingError)
        expect(cleaned.size).to eq(pattern.size)
        expect(cleaned.count(fallback)).to eq(pattern.count(true))
      end
    end
  end

  describe "indexed apply with random positions" do
    it "places SKIPPED at correct indices for collect" do
      strategy = ApiClient::Processing::ErrorStrategy.collect

      property_of { range(3, 20) }.check(10) do |size|
        results = Array.new(size)
        fail_indices = (0...size).to_a.sample(size / 3)

        (0...size).each do |i|
          if fail_indices.include?(i)
            strategy.apply_indexed(i, RuntimeError.new("err"), results)
          else
            results[i] = "ok_#{i}"
          end
        end

        fail_indices.each do |i|
          expect(results[i].equal?(skipped)).to be true
        end

        success_indices = (0...size).to_a - fail_indices
        success_indices.each do |i|
          expect(results[i]).to eq("ok_#{i}")
        end
      end
    end
  end

  describe "nil vs SKIPPED distinction" do
    it "finalize preserves nil results but removes SKIPPED" do
      strategy = ApiClient::Processing::ErrorStrategy.skip
      results = [nil, "a", skipped, nil, "b", skipped]
      cleaned = strategy.finalize(results, [], StandardError)
      expect(cleaned).to eq([nil, "a", nil, "b"])
    end
  end
end
