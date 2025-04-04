require "spec_helper"
require "api_client"

RSpec.describe "Configuration validation", :integration do
  describe "PoolConfig validation" do
    it "rejects non-integer pool size" do
      config = ApiClient::PoolConfig.new
      expect { config.size = 2.5 }.to raise_error(ApiClient::ConfigurationError, /positive Integer/)
    end

    it "rejects zero pool size" do
      config = ApiClient::PoolConfig.new
      expect { config.size = 0 }.to raise_error(ApiClient::ConfigurationError, /positive Integer/)
    end

    it "rejects negative pool size" do
      config = ApiClient::PoolConfig.new
      expect { config.size = -1 }.to raise_error(ApiClient::ConfigurationError, /positive Integer/)
    end

    it "rejects string pool size" do
      config = ApiClient::PoolConfig.new
      expect { config.size = "big" }.to raise_error(ApiClient::ConfigurationError, /positive Integer/)
    end

    it "accepts valid pool size" do
      config = ApiClient::PoolConfig.new
      config.size = 8
      expect(config.size).to eq(8)
    end

    it "rejects non-numeric pool timeout" do
      config = ApiClient::PoolConfig.new
      expect { config.timeout = "slow" }.to raise_error(ApiClient::ConfigurationError, /positive Numeric/)
    end

    it "rejects zero pool timeout" do
      config = ApiClient::PoolConfig.new
      expect { config.timeout = 0 }.to raise_error(ApiClient::ConfigurationError, /positive Numeric/)
    end

    it "accepts float pool timeout" do
      config = ApiClient::PoolConfig.new
      config.timeout = 2.5
      expect(config.timeout).to eq(2.5)
    end
  end

  describe "ProcessorConfig validation" do
    it "rejects non-integer ractor_pool_size" do
      config = ApiClient::ProcessorConfig.new
      expect { config.ractor_pool_size = 1.5 }.to raise_error(ApiClient::ConfigurationError)
    end

    it "rejects zero ractor_pool_size" do
      config = ApiClient::ProcessorConfig.new
      expect { config.ractor_pool_size = 0 }.to raise_error(ApiClient::ConfigurationError)
    end

    it "rejects negative async_pool_size" do
      config = ApiClient::ProcessorConfig.new
      expect { config.async_pool_size = -2 }.to raise_error(ApiClient::ConfigurationError)
    end

    it "accepts zero min_batch_size" do
      config = ApiClient::ProcessorConfig.new
      config.ractor_min_batch_size = 0
      expect(config.ractor_min_batch_size).to eq(0)
    end

    it "rejects negative min_batch_size" do
      config = ApiClient::ProcessorConfig.new
      expect { config.ractor_min_batch_size = -1 }.to raise_error(ApiClient::ConfigurationError)
    end

    it "rejects negative min_payload_size" do
      config = ApiClient::ProcessorConfig.new
      expect { config.ractor_min_payload_size = -1 }.to raise_error(ApiClient::ConfigurationError)
    end

    it "accepts valid concurrent_processor_pool_size" do
      config = ApiClient::ProcessorConfig.new
      config.concurrent_processor_pool_size = 16
      expect(config.concurrent_processor_pool_size).to eq(16)
    end
  end

  describe "Configuration#merge" do
    it "merges nested pool config" do
      config = ApiClient::Configuration.new
      merged = config.merge(pool: {size: 20, timeout: 10})

      expect(merged.pool_config.size).to eq(20)
      expect(merged.pool_config.timeout).to eq(10)
    end

    it "returns a new config with overrides applied" do
      config = ApiClient::Configuration.new
      merged = config.merge(pool: {size: 99})

      expect(merged.pool_config.size).to eq(99)
      expect(merged).not_to equal(config)
    end

    it "ignores unknown top-level keys" do
      config = ApiClient::Configuration.new
      merged = config.merge(nonexistent_key: "value")
      expect(merged).to be_a(ApiClient::Configuration)
    end
  end

  describe "Base#normalize_args unknown key detection" do
    it "raises ArgumentError for unknown keys in options hash" do
      client = client_for_server
      expect {
        client.get("/health", {params: {a: 1}, bogus: true})
      }.to raise_error(ArgumentError, /Unknown keys.*bogus/)
    end

    it "allows plain hash as params without raising" do
      client = client_for_server
      response = client.get("/health", {page: 1})
      expect(response.status).to eq(200)
    end

    it "allows keyword-style params and headers" do
      client = client_for_server
      response = client.get("/health", params: {}, headers: {})
      expect(response.status).to eq(200)
    end
  end
end
