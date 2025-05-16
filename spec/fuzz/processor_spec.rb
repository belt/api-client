require "spec_helper"
require "api_client"

RSpec.describe "Processor fuzzing", :fuzz, :integration do
  let(:client) { client_for_server }

  def mock_responses(count)
    count.times.map do |i|
      body = {id: i, data: "item-#{i}"}.to_json
      env = Faraday::Env.new.tap do |e|
        e.status = 200
        e.body = body
        e.response_headers = {"content-type" => "application/json"}
      end
      Faraday::Response.new(env)
    end
  end

  describe ApiClient::Processing::ConcurrentProcessor do
    let(:processor) { described_class.new(pool_size: 2, min_batch_size: 1) }

    it "handles random batch sizes" do
      property_of { range(1, 20) }.check(10) do |size|
        responses = mock_responses(size)
        results = processor.map(responses)

        expect(results.size).to eq(size)
        results.each_with_index do |r, i|
          expect(r["id"]).to eq(i)
        end
      end
    end

    it "handles random extractors" do
      responses = mock_responses(5)

      [:body, :status, :headers, :identity].each do |extractor|
        recipe = ApiClient::Transforms::Recipe.new(extract: extractor, transform: :identity)
        expect { processor.map(responses, recipe: recipe) }
          .not_to raise_error
      end
    end

    it "handles custom proc extractors" do
      responses = mock_responses(5)

      property_of {
        choose(
          ->(r) { r.body },
          ->(r) { r.status.to_s },
          ->(r) { r.body.upcase }
        )
      }.check(5) do |extractor|
        recipe = ApiClient::Transforms::Recipe.new(extract: extractor, transform: :identity)
        expect { processor.map(responses, recipe: recipe) }
          .not_to raise_error
      end
    end

    it "handles select with random predicates" do
      responses = mock_responses(10)

      property_of { range(0, 9) }.check(5) do |threshold|
        results = processor.select(responses) do |data|
          data["id"] > threshold
        end

        expect(results.size).to eq(9 - threshold)
      end
    end

    it "handles reduce with random initial values" do
      responses = mock_responses(5)

      property_of { range(0, 100) }.check(5) do |initial|
        result = processor.reduce(responses, initial) do |acc, data|
          acc + data["id"]
        end

        expect(result).to eq(initial + (0..4).sum)
      end
    end
  end

  describe "error strategy fuzzing" do
    let(:processor) do
      ApiClient::Processing::ConcurrentProcessor.new(
        pool_size: 2, min_batch_size: 1
      )
    end

    def responses_with_bad_json(count, bad_indices)
      count.times.map do |i|
        body = bad_indices.include?(i) ? "invalid json" : {id: i}.to_json
        env = Faraday::Env.new.tap do |e|
          e.status = 200
          e.body = body
        end
        Faraday::Response.new(env)
      end
    end

    it "skip strategy removes failed items" do
      responses = responses_with_bad_json(5, [1, 3])
      results = processor.map(responses, errors: ApiClient::Processing::ErrorStrategy.skip)

      expect(results.size).to eq(3)
      expect(results.map { |r| r["id"] }).to eq([0, 2, 4])
    end

    it "replace strategy substitutes fallback" do
      responses = responses_with_bad_json(5, [1, 3])
      fallback = {id: -1}
      results = processor.map(responses,
        errors: ApiClient::Processing::ErrorStrategy.replace(fallback))

      expect(results.size).to eq(5)
      expect(results[1]).to eq(fallback)
      expect(results[3]).to eq(fallback)
    end

    it "collect strategy raises with partial results" do
      responses = responses_with_bad_json(5, [2])

      expect {
        processor.map(responses, errors: ApiClient::Processing::ErrorStrategy.collect)
      }.to raise_error(ApiClient::ConcurrentProcessingError) do |error|
        expect(error.partial_results.size).to eq(4)
        expect(error.failure_count).to eq(1)
      end
    end
  end
end
