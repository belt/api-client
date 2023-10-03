require "faraday"

RSpec.shared_examples "ractor processor" do
  let(:json_bodies) do
    5.times.map { |i| {"id" => i + 1, "name" => "Item #{i + 1}"}.to_json }
  end

  let(:mock_responses) do
    json_bodies.map do |body|
      instance_double(Faraday::Response, body: body, status: 200, headers: {})
    end
  end

  describe "#map" do
    it "transforms items in parallel" do
      results = processor.map(mock_responses)

      expect(results.size).to eq(5)
      expect(results.first).to eq({"id" => 1, "name" => "Item 1"})
    end

    it "applies user block after transform" do
      results = processor.map(mock_responses) do |parsed|
        parsed["id"] * 10
      end

      expect(results).to eq([10, 20, 30, 40, 50])
    end

    it "returns empty array for empty input" do
      expect(processor.map([])).to eq([])
    end

    it "handles identity transform" do
      results = processor.map(mock_responses, recipe: ApiClient::Transforms::Recipe.identity)
      expect(results).to eq(json_bodies)
    end

    it "computes checksums" do
      recipe = ApiClient::Transforms::Recipe.new(extract: :body, transform: :sha256)
      results = processor.map(mock_responses, recipe: recipe)

      expect(results.size).to eq(5)
      expect(results.first).to match(/\A[a-f0-9]{64}\z/)
    end
  end

  describe "#select" do
    it "filters items based on predicate" do
      results = processor.select(mock_responses) do |parsed|
        parsed["id"] > 3
      end

      expect(results.size).to eq(2)
    end

    it "returns original items, not transformed" do
      results = processor.select(mock_responses) do |parsed|
        parsed["id"] == 1
      end

      expect(results.first).to eq(mock_responses.first)
    end
  end

  describe "#reduce" do
    it "reduces items to single value" do
      result = processor.reduce(mock_responses, 0) do |sum, parsed|
        sum + parsed["id"]
      end

      expect(result).to eq(15) # 1+2+3+4+5
    end

    it "returns initial value for empty input" do
      result = processor.reduce([], 42) { |a, b| a + b }
      expect(result).to eq(42)
    end
  end
end

RSpec.shared_examples "ractor error handling" do
  let(:bad_json) { "not valid json" }
  let(:good_json) { '{"id": 1}' }

  let(:mixed_responses) do
    [
      instance_double(Faraday::Response, body: good_json, status: 200, headers: {}),
      instance_double(Faraday::Response, body: bad_json, status: 200, headers: {}),
      instance_double(Faraday::Response, body: good_json, status: 200, headers: {})
    ]
  end

  describe "errors: fail_fast" do
    it "raises on first error" do
      expect {
        processor.map(mixed_responses, errors: ApiClient::Processing::ErrorStrategy.fail_fast)
      }.to raise_error(JSON::ParserError)
    end
  end

  describe "errors: collect" do
    it "raises RactorProcessingError with all failures" do
      expect {
        processor.map(mixed_responses, errors: ApiClient::Processing::ErrorStrategy.collect)
      }.to raise_error(ApiClient::RactorProcessingError) do |error|
        expect(error.failure_count).to eq(1)
        expect(error.success_count).to eq(2)
        expect(error.partial_results.size).to eq(2)
      end
    end
  end

  describe "errors: skip" do
    it "returns only successful results" do
      results = processor.map(mixed_responses, errors: ApiClient::Processing::ErrorStrategy.skip)

      expect(results.size).to eq(2)
      expect(results).to all(eq({"id" => 1}))
    end
  end

  describe "errors: replace" do
    it "replaces failures with fallback value" do
      results = processor.map(
        mixed_responses,
        errors: ApiClient::Processing::ErrorStrategy.replace({"error" => true})
      )

      expect(results.size).to eq(3)
      expect(results[1]).to eq({"error" => true})
    end
  end
end
