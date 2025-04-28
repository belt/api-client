require "spec_helper"
require "api_client"

RSpec.describe "Configuration fuzzing", :fuzz do
  describe "PoolConfig with random invalid values" do
    it "rejects all non-positive-integer sizes" do
      property_of {
        choose(0, -1, -100, 1.5, "abc", nil, [], {})
      }.check(20) do |value|
        config = ApiClient::PoolConfig.new
        expect { config.size = value }.to raise_error(ApiClient::ConfigurationError)
      end
    end

    it "accepts all positive integer sizes" do
      property_of { range(1, 1000) }.check(20) do |value|
        config = ApiClient::PoolConfig.new
        config.size = value
        expect(config.size).to eq(value)
      end
    end

    it "rejects all non-positive-numeric timeouts" do
      property_of {
        choose(0, -1, -0.5, "fast", nil, [], {})
      }.check(20) do |value|
        config = ApiClient::PoolConfig.new
        expect { config.timeout = value }.to raise_error(ApiClient::ConfigurationError)
      end
    end

    it "accepts all positive numeric timeouts" do
      property_of { choose(0.1, 0.5, 1, 5, 30, 60, 120) }.check(10) do |value|
        config = ApiClient::PoolConfig.new
        config.timeout = value
        expect(config.timeout).to eq(value)
      end
    end
  end

  describe "ProcessorConfig with random invalid values" do
    it "rejects non-positive-integer pool sizes across all processor types" do
      attrs = %i[ractor_pool_size async_pool_size concurrent_processor_pool_size]

      property_of {
        [choose(*attrs), choose(0, -1, 2.5, "x", nil)]
      }.check(30) do |attr, value|
        config = ApiClient::ProcessorConfig.new
        expect { config.public_send(:"#{attr}=", value) }.to raise_error(ApiClient::ConfigurationError)
      end
    end

    it "rejects negative min_batch_sizes" do
      attrs = %i[ractor_min_batch_size async_min_batch_size concurrent_processor_min_batch_size]

      property_of {
        [choose(*attrs), choose(-1, -100, 1.5, "x", nil)]
      }.check(30) do |attr, value|
        config = ApiClient::ProcessorConfig.new
        expect { config.public_send(:"#{attr}=", value) }.to raise_error(ApiClient::ConfigurationError)
      end
    end
  end

  describe "RetryConfig to_h consistency" do
    it "returns empty retry_statuses when max is 0" do
      config = ApiClient::RetryConfig.new
      config.max = 0
      h = config.to_h
      expect(h[:retry_statuses]).to eq([])
      expect(h[:max]).to eq(0)
    end

    it "returns frozen hash" do
      config = ApiClient::RetryConfig.new
      expect(config.to_h).to be_frozen
    end
  end

  describe "CircuitConfig to_h caching" do
    it "invalidates cache after track_only" do
      config = ApiClient::CircuitConfig.new
      first = config.to_h
      config.track_only(Timeout::Error)
      second = config.to_h

      expect(first[:tracked_errors]).to be_nil
      expect(second[:tracked_errors]).to eq(["Timeout::Error"])
    end
  end

  describe "JwtConfig defaults" do
    it "has secure defaults" do
      config = ApiClient::JwtConfig.new
      expect(config.allow_hmac).to be false
      expect(config.algorithm).to eq("RS256")
      expect(config.allowed_algorithms).not_to include("HS256")
    end
  end
end
