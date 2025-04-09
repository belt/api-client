require "spec_helper"
require "api_client"

RSpec.describe "Processor resilience", :integration do
  def mock_responses(count, &block)
    count.times.map do |i|
      body = block ? block.call(i) : {id: i}.to_json
      env = Faraday::Env.new.tap do |e|
        e.status = 200
        e.body = body
        e.response_headers = {"content-type" => "application/json"}
      end
      Faraday::Response.new(env)
    end
  end

  describe ApiClient::Processing::ConcurrentProcessor do
    let(:processor) { described_class.new(pool_size: 4, min_batch_size: 1) }

    describe "malformed input handling" do
      it "handles nil bodies with skip strategy" do
        responses = mock_responses(5) { |i| i.even? ? nil : {id: i}.to_json }

        results = processor.map(responses, errors: ApiClient::Processing::ErrorStrategy.skip)
        expect(results.size).to eq(2) # Only odd indices have valid JSON
      end

      it "handles empty string bodies" do
        responses = mock_responses(5) { |i| i == 2 ? "" : {id: i}.to_json }

        results = processor.map(responses, errors: ApiClient::Processing::ErrorStrategy.skip)
        expect(results.size).to eq(4)
      end

      it "handles deeply nested JSON" do
        deep_json = 10.times.reduce({value: 1}) { |acc, _| {nested: acc} }.to_json
        responses = mock_responses(3) { deep_json }

        results = processor.map(responses)
        expect(results.size).to eq(3)
        expect(results.first).to have_key("nested")
      end
    end

    describe "large payload handling" do
      it "processes large JSON arrays" do
        large_array = (1..1000).to_a.to_json
        responses = mock_responses(5) { large_array }

        results = processor.map(responses)
        expect(results.size).to eq(5)
        expect(results.first.size).to eq(1000)
      end

      it "processes large JSON objects" do
        large_obj = (1..100).map { |i| ["key_#{i}", "value_#{i}"] }.to_h.to_json
        responses = mock_responses(5) { large_obj }

        results = processor.map(responses)
        expect(results.size).to eq(5)
        expect(results.first.keys.size).to eq(100)
      end
    end

    describe "concurrent error handling" do
      it "handles errors in multiple items simultaneously" do
        responses = mock_responses(10) { |i| i % 3 == 0 ? "bad" : {id: i}.to_json }

        results = processor.map(responses, errors: ApiClient::Processing::ErrorStrategy.skip)
        # Items 0, 3, 6, 9 are bad
        expect(results.size).to eq(6)
      end

      it "fail_fast stops on first error" do
        responses = mock_responses(10) { |i| i == 5 ? "bad" : {id: i}.to_json }

        expect {
          processor.map(responses, errors: ApiClient::Processing::ErrorStrategy.fail_fast)
        }.to raise_error(JSON::ParserError)
      end
    end

    describe "empty input handling" do
      it "handles empty array" do
        results = processor.map([])
        expect(results).to eq([])
      end

      it "handles single item" do
        responses = mock_responses(1)
        results = processor.map(responses)
        expect(results.size).to eq(1)
      end
    end
  end

  describe "transform resilience" do
    let(:processor) do
      ApiClient::Processing::ConcurrentProcessor.new(
        pool_size: 2, min_batch_size: 1
      )
    end

    it "handles identity transform" do
      responses = mock_responses(5)
      results = processor.map(responses, recipe: ApiClient::Transforms::Recipe.identity)

      expect(results.size).to eq(5)
      expect(results.first).to be_a(String)
    end

    it "handles sha256 transform" do
      responses = mock_responses(5)
      recipe = ApiClient::Transforms::Recipe.new(extract: :body, transform: :sha256)
      results = processor.map(responses, recipe: recipe)

      expect(results.size).to eq(5)
      expect(results.first).to match(/\A[a-f0-9]{64}\z/)
    end

    it "handles unknown transform with error" do
      responses = mock_responses(5)
      recipe = ApiClient::Transforms::Recipe.new(extract: :body, transform: :unknown)

      # Unknown transform causes errors which get collected
      expect {
        processor.map(responses, recipe: recipe,
          errors: ApiClient::Processing::ErrorStrategy.fail_fast)
      }.to raise_error(ArgumentError)
    end
  end
end
