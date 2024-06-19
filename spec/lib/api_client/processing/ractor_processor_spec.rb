require "spec_helper"
require "api_client"
require "api_client/processing/ractor_processor"
require "faraday"

RSpec.describe ApiClient::Processing::RactorProcessor,
  skip: !defined?(Ractor::Port) && "Ractor::Port requires Ruby 4.0+" do
  # Use instance pool to avoid global state in tests
  subject(:processor) {
    described_class.new(
      pool: :instance, pool_size: 2, min_batch_size: 1, min_payload_size: 1
    )
  }

  after { processor.shutdown }

  it_behaves_like "ractor processor"
  it_behaves_like "ractor error handling"

  describe "#initialize" do
    it "uses global pool by default" do
      default_processor = described_class.new
      expect(default_processor.pool).to eq(described_class.global_pool)
    end

    it "creates instance pool when requested" do
      instance_processor = described_class.new(pool: :instance, pool_size: 4)
      expect(instance_processor.pool.size).to eq(4)
      instance_processor.shutdown
    end

    it "accepts injected pool" do
      custom_pool = ApiClient::Processing::RactorPool.new(size: 3)
      injected_processor = described_class.new(pool: custom_pool)
      expect(injected_processor.pool).to eq(custom_pool)
      custom_pool.shutdown
    end

    it "uses configuration defaults" do
      ApiClient.configure do |config|
        config.processor_config.ractor_min_batch_size = 10
      end

      config_processor = described_class.new(pool: :instance)
      expect(config_processor.min_batch_size).to eq(10)
      expect(config_processor.default_error_strategy.strategy).to eq(:fail_fast)
      config_processor.shutdown
    end
  end

  describe "sequential fallback" do
    let(:small_responses) do
      2.times.map { |i| instance_double(
        Faraday::Response, body: {id: i}.to_json, status: 200, headers: {}) }
    end

    it "uses sequential processing for small batches" do
      large_batch_processor = described_class.new(
        pool: :instance, min_batch_size: 10, min_payload_size: 1
      )

      # Should not start pool workers for small batch
      results = large_batch_processor.map(small_responses)

      expect(results.size).to eq(2)
      expect(large_batch_processor.pool.worker_count).to eq(0)
      large_batch_processor.shutdown
    end

    it "uses sequential processing for small payloads" do
      large_payload_processor = described_class.new(
        pool: :instance, min_batch_size: 1, min_payload_size: 100_000
      )

      results = large_payload_processor.map(small_responses)

      expect(results.size).to eq(2)
      expect(large_payload_processor.pool.worker_count).to eq(0)
      large_payload_processor.shutdown
    end
  end

  describe "custom extractors" do
    let(:responses) do
      3.times.map do |i|
        instance_double(Faraday::Response,
          body: {id: i}.to_json,
          status: 200 + i,
          headers: {"X-Index" => i.to_s})
      end
    end

    it "extracts status" do
      results = processor.map(responses, recipe: ApiClient::Transforms::Recipe.status)
      expect(results).to eq([200, 201, 202])
    end

    it "extracts headers" do
      results = processor.map(responses, recipe: ApiClient::Transforms::Recipe.headers)
      expect(results.first).to eq({"X-Index" => "0"})
    end

    it "accepts proc extractor" do
      custom_extractor = ->(r) { "status:#{r.status}" }
      recipe = ApiClient::Transforms::Recipe.new(extract: custom_extractor, transform: :identity)
      results = processor.map(responses, recipe: recipe)
      expect(results).to eq(["status:200", "status:201", "status:202"])
    end
  end

  describe "hooks integration" do
    let(:responses) do
      3.times.map { |i| instance_double(
        Faraday::Response, body: {id: i}.to_json, status: 200, headers: {}) }
    end

    it "instruments ractor_start" do
      events = []
      subscriber = ApiClient::Hooks.subscribe(:ractor_start) do |*args|
        events << ActiveSupport::Notifications::Event.new(*args)
      end

      processor.map(responses)

      expect(events.size).to eq(1)
      expect(events.first.payload).to include(operation: :map, count: 3)
    ensure
      ApiClient::Hooks.unsubscribe(subscriber)
    end

    it "instruments ractor_complete" do
      events = []
      subscriber = ApiClient::Hooks.subscribe(:ractor_complete) do |*args|
        events << ActiveSupport::Notifications::Event.new(*args)
      end

      processor.map(responses)

      expect(events.size).to eq(1)
      expect(events.first.payload).to include(operation: :map, input_count: 3, output_count: 3)
    ensure
      ApiClient::Hooks.unsubscribe(subscriber)
    end

    it "instruments ractor_error" do
      bad_responses = [instance_double(Faraday::Response,
        body: "not json", status: 200, headers: {}
      )]
      events = []
      subscriber = ApiClient::Hooks.subscribe(:ractor_error) do |*args|
        events << ActiveSupport::Notifications::Event.new(*args)
      end

      processor.map(bad_responses, errors: ApiClient::Processing::ErrorStrategy.skip)

      expect(events.size).to eq(1)
      expect(events.first.payload).to include(index: 0, strategy: :skip)
    ensure
      ApiClient::Hooks.unsubscribe(subscriber)
    end
  end

  describe ".global_pool" do
    after { described_class.reset_global_pool! }

    it "returns singleton pool" do
      pool1 = described_class.global_pool
      pool2 = described_class.global_pool
      expect(pool1).to be(pool2)
    end

    it "uses configured pool size" do
      ApiClient.configure { |c| c.processor_config.ractor_pool_size = 3 }
      described_class.reset_global_pool!

      expect(described_class.global_pool.size).to eq(3)
    end
  end

  describe ".reset_global_pool!" do
    it "shuts down and clears global pool" do
      old_pool = described_class.global_pool
      described_class.reset_global_pool!
      new_pool = described_class.global_pool

      expect(new_pool).not_to be(old_pool)
    end
  end
end

RSpec.describe ApiClient::RactorProcessingError do
  subject(:error) { described_class.new(results, failures) }

  let(:results) { [{"id" => 1}, nil, {"id" => 3}] }
  let(:failures) { [{index: 1, item: "bad", error: StandardError.new("parse error")}] }

  describe "#partial_results" do
    it "returns non-nil results" do
      expect(error.partial_results).to eq([{"id" => 1}, {"id" => 3}])
    end
  end

  describe "#success_count" do
    it "counts non-nil results" do
      expect(error.success_count).to eq(2)
    end
  end

  describe "#failure_count" do
    it "counts failures" do
      expect(error.failure_count).to eq(1)
    end
  end

  describe "#message" do
    it "includes failure count" do
      expect(error.message).to include("1 items failed")
    end
  end
end
