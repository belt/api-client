require "spec_helper"
require "api_client"
require "api_client/processing/registry"
require "faraday"

RSpec.describe ApiClient::Processing::Registry do
  before { described_class.reset! }

  after { described_class.reset! }

  describe ".detect" do
    it "returns a processor symbol or nil" do
      result = described_class.detect
      expect(result).to be_nil.or be_a(Symbol)
    end
  end

  describe ".available?" do
    it "returns true for sequential" do
      expect(described_class.available?(:sequential)).to be true
    end

    it "returns false for unknown processor" do
      expect(described_class.available?(:unknown)).to be false
    end

    it "returns truthy for ractor on Ruby 3+" do
      expect(described_class.available?(:ractor)).to be_truthy
    end

    it "returns truthy for concurrent when gem available" do
      expect(described_class.available?(:concurrent)).to be_truthy
    end
  end

  describe ".available_processors" do
    it "returns array of available processor symbols including sequential" do
      result = described_class.available_processors
      expect(result).to be_an(Array)
      expect(result).to include(:sequential)
      expect(result).to be_frozen
    end
  end

  describe ".resolve" do
    it "returns SequentialProcessor for :sequential" do
      expect(described_class.resolve(:sequential)).to eq(ApiClient::Processing::SequentialProcessor)
    end

    it "returns RactorProcessor for :ractor" do
      expect(described_class.resolve(:ractor)).to eq(ApiClient::Processing::RactorProcessor)
    end

    it "returns ConcurrentProcessor for :concurrent" do
      expect(described_class.resolve(:concurrent)).to eq(ApiClient::Processing::ConcurrentProcessor)
    end

    it "raises ArgumentError for unknown processor" do
      expect { described_class.resolve(:unknown) }
        .to raise_error(ArgumentError, /Unknown processor/)
    end
  end

  describe ".processor_name" do
    it "returns :sequential for SequentialProcessor" do
      expect(described_class.processor_name(ApiClient::Processing::SequentialProcessor))
        .to eq(:sequential)
    end

    it "returns nil for unknown class" do
      expect(described_class.processor_name(String)).to be_nil
    end
  end

  describe ".reset!" do
    it "clears memoized state" do
      described_class.available?(:sequential)
      described_class.available_processors

      described_class.reset!

      # Should not raise and should recompute
      expect(described_class.available?(:sequential)).to be true
    end
  end
end

RSpec.describe ApiClient::Processing::SequentialProcessor do
  subject(:processor) { described_class.new }

  describe ".available?" do
    it "returns true" do
      expect(described_class.available?).to be true
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

    it "transforms responses" do
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
  end

  describe "#select" do
    let(:responses) do
      5.times.map { |i| instance_double(
        Faraday::Response, body: {id: i, even: i.even?}.to_json, status: 200, headers: {}) }
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

    it "reduces transformed values" do
      result = processor.reduce(responses, 0) { |acc, h| acc + h["value"] }
      expect(result).to eq(6)
    end
  end

  describe "#processing_error_class" do
    it "returns ProcessingError" do
      expect(processor.processing_error_class).to eq(ApiClient::ProcessingError)
    end
  end
end
