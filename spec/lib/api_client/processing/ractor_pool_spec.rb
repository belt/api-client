require "spec_helper"
require "api_client"
require "api_client/processing/ractor_pool"

RSpec.describe ApiClient::Processing::RactorPool,
  skip: !defined?(Ractor::Port) && "Ractor::Port requires Ruby 4.0+" do
  subject(:pool) { described_class.new(size: 2) }

  after { pool.shutdown }

  describe "#initialize" do
    it "sets pool size" do
      expect(pool.size).to eq(2)
    end

    it "defaults to CPU count" do
      default_pool = described_class.new
      expect(default_pool.size).to eq(Etc.nprocessors)
      default_pool.shutdown
    end

    it "does not start workers until first use" do
      expect(pool.worker_count).to eq(0)
    end
  end

  describe "#process" do
    let(:items) { %w[a b c d e] }
    let(:extractor) { ->(item) { item } }

    it "processes items in parallel" do
      results, errors = pool.process(items, extractor: extractor, transform: :identity)

      expect(results).to eq(items)
      expect(errors).to be_empty
    end

    it "maintains order" do
      results, _errors = pool.process((1..10).to_a, extractor: ->(i) { i.to_s },
        transform: :identity)

      expect(results).to eq((1..10).map(&:to_s))
    end

    it "returns empty for empty input" do
      results, errors = pool.process([], extractor: extractor, transform: :identity)

      expect(results).to eq([])
      expect(errors).to eq([])
    end

    it "applies json transform" do
      json_items = [{a: 1}.to_json, {b: 2}.to_json]
      results, _errors = pool.process(json_items, extractor: ->(i) { i }, transform: :json)

      expect(results).to eq([{"a" => 1}, {"b" => 2}])
    end

    it "applies sha256 transform" do
      results, _errors = pool.process(%w[hello world], extractor: ->(i) { i }, transform: :sha256)

      expect(results.size).to eq(2)
      expect(results.first).to eq(Digest::SHA256.hexdigest("hello"))
    end

    it "collects errors without stopping" do
      items_with_bad = ['{"valid": true}', "not json", '{"also": "valid"}']
      results, errors = pool.process(items_with_bad, extractor: ->(i) { i }, transform: :json)

      expect(errors.size).to eq(1)
      expect(errors.first[:index]).to eq(1)
      expect(results[0]).to eq({"valid" => true})
      expect(results[2]).to eq({"also" => "valid"})
    end

    it "raises ArgumentError for unknown transform" do
      expect {
        pool.process(%w[a], extractor: ->(i) { i }, transform: :bogus)
      }.to raise_error(ArgumentError, /Unknown transform/)
    end

    it "handles more items than workers" do
      many_items = (1..20).map(&:to_s)
      results, errors = pool.process(many_items, extractor: ->(i) { i }, transform: :identity)

      expect(results).to eq(many_items)
      expect(errors).to be_empty
    end
  end

  describe "#shutdown" do
    it "terminates workers" do
      pool.process(%w[a b], extractor: ->(i) { i }, transform: :identity)
      expect(pool.worker_count).to eq(2)

      pool.shutdown

      expect(pool.running?).to be false
    end

    it "is idempotent" do
      pool.shutdown
      expect { pool.shutdown }.not_to raise_error
    end

    it "prevents further processing" do
      pool.shutdown

      expect {
        pool.process(%w[a], extractor: ->(i) { i }, transform: :identity)
      }.to raise_error(/shutdown/)
    end

    it "handles already-terminated workers gracefully" do
      pool.process(%w[a b], extractor: ->(i) { i }, transform: :identity)
      # Force-terminate one worker before shutdown
      worker = pool.instance_variable_get(:@workers).first
      worker[:ractor].send(:shutdown)
      sleep 0.05
      expect { pool.shutdown }.not_to raise_error
    end
  end

  describe "#running?" do
    it "returns false before first use" do
      expect(pool.running?).to be false
    end

    it "returns true after first use" do
      pool.process(%w[a], extractor: ->(i) { i }, transform: :identity)
      expect(pool.running?).to be true
    end

    it "returns false after shutdown" do
      pool.process(%w[a], extractor: ->(i) { i }, transform: :identity)
      pool.shutdown
      expect(pool.running?).to be false
    end
  end
end
