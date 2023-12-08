require "spec_helper"
require "api_client"

RSpec.describe ApiClient::RetryConfig do
  subject(:config) { described_class.new }

  describe "default values" do
    it "sets max to 2" do
      expect(config.max).to eq(2)
    end

    it "sets interval to 0.5" do
      expect(config.interval).to eq(0.5)
    end

    it "sets interval_randomness to 0.5" do
      expect(config.interval_randomness).to eq(0.5)
    end

    it "sets backoff_factor to 2" do
      expect(config.backoff_factor).to eq(2)
    end

    it "sets retry_statuses" do
      expect(config.retry_statuses).to eq([429, 500, 502, 503, 504])
    end

    it "sets retryable methods" do
      expect(config.methods).to include(:get, :head, :put, :delete)
    end

    it "sets retryable exceptions" do
      expect(config.exceptions).to include(Faraday::TimeoutError)
    end
  end

  describe "#to_h" do
    it "returns hash with all settings" do
      hash = config.to_h
      expect(hash).to include(:max, :interval, :backoff_factor)
    end
  end
end
