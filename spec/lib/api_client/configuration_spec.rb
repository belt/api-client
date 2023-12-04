require "spec_helper"
require "api_client"

RSpec.describe ApiClient::Configuration do
  subject(:config) { described_class.new }

  describe "default values" do
    it "sets service_uri to localhost" do
      expect(config.service_uri).to eq("http://localhost:8080")
    end

    it "sets base_path to /" do
      expect(config.base_path).to eq("/")
    end

    it "sets open_timeout to 5" do
      expect(config.open_timeout).to eq(5)
    end

    it "sets read_timeout to 30" do
      expect(config.read_timeout).to eq(30)
    end

    it "sets write_timeout to 10" do
      expect(config.write_timeout).to eq(10)
    end

    it "sets on_error to :raise" do
      expect(config.on_error).to eq(:raise)
    end

    it "sets default Accept header" do
      expect(config.default_headers["Accept"]).to eq("application/json")
    end

    it "sets default Content-Type header" do
      expect(config.default_headers["Content-Type"]).to eq("application/json")
    end
  end

  describe "#retry" do
    it "returns RetryConfig" do
      expect(config.retry).to be_a(ApiClient::RetryConfig)
    end

    it "yields config when block given" do
      config.retry { |r| r.max = 10 }
      expect(config.retry.max).to eq(10)
    end
  end

  describe "#circuit" do
    it "returns CircuitConfig" do
      expect(config.circuit).to be_a(ApiClient::CircuitConfig)
    end

    it "yields config when block given" do
      config.circuit { |c| c.threshold = 10 }
      expect(config.circuit.threshold).to eq(10)
    end
  end

  describe "#jwt" do
    it "returns JwtConfig" do
      expect(config.jwt).to be_a(ApiClient::JwtConfig)
    end

    it "yields config when block given" do
      config.jwt { |j| j.algorithm = "ES256" }
      expect(config.jwt.algorithm).to eq("ES256")
    end
  end

  describe "#pool" do
    it "returns PoolConfig" do
      expect(config.pool).to be_a(ApiClient::PoolConfig)
    end

    it "yields config when block given" do
      config.pool { |p| p.size = 20 }
      expect(config.pool.size).to eq(20)
    end

    it "is accessible via pool_config reader" do
      expect(config.pool_config).to be_a(ApiClient::PoolConfig)
    end
  end

  describe "#on" do
    it "registers hooks for events" do
      handler = proc { |_| }
      config.on(:request_start, &handler)
      expect(config.hooks[:request_start]).to include(handler)
    end

    it "allows multiple handlers per event" do
      config.on(:request_start) { "first" }
      config.on(:request_start) { "second" }
      expect(config.hooks[:request_start].size).to eq(2)
    end
  end

  describe "#merge" do
    it "returns new Configuration instance" do
      merged = config.merge(read_timeout: 60)
      expect(merged).to be_a(described_class)
    end

    it "returns different object than original" do
      merged = config.merge(read_timeout: 60)
      expect(merged).not_to eq(config)
    end

    it "applies read_timeout override" do
      merged = config.merge(read_timeout: 60)
      expect(merged.read_timeout).to eq(60)
    end

    it "applies open_timeout override" do
      merged = config.merge(open_timeout: 10)
      expect(merged.open_timeout).to eq(10)
    end

    it "preserves original config" do
      config.merge(read_timeout: 60)
      expect(config.read_timeout).to eq(30)
    end

    it "merges nested retry config max" do
      merged = config.merge(retry: {max: 5, interval: 1.0})
      expect(merged.retry_config.max).to eq(5)
    end

    it "merges nested retry config interval" do
      merged = config.merge(retry: {max: 5, interval: 1.0})
      expect(merged.retry_config.interval).to eq(1.0)
    end

    it "merges nested pool config size" do
      merged = config.merge(pool: {size: 20, timeout: 10})
      expect(merged.pool_config.size).to eq(20)
    end

    it "merges nested pool config timeout" do
      merged = config.merge(pool: {size: 20, timeout: 10})
      expect(merged.pool_config.timeout).to eq(10)
    end

    it "ignores unknown keys" do
      merged = config.merge(nonexistent_key: "value")
      expect(merged).to be_a(described_class)
    end
  end

  describe "#to_faraday_options" do
    subject(:options) { config.to_faraday_options }

    it "includes open_timeout" do
      expect(options[:request][:open_timeout]).to eq(5)
    end

    it "includes read_timeout" do
      expect(options[:request][:read_timeout]).to eq(30)
    end

    it "includes write_timeout" do
      expect(options[:request][:write_timeout]).to eq(10)
    end
  end

  describe "processor defaults" do
    it "sets ractor_pool_size to CPU count" do
      expect(config.processor_config.ractor_pool_size).to eq(Etc.nprocessors)
    end

    it "sets async_pool_size to CPU count" do
      expect(config.processor_config.async_pool_size).to eq(Etc.nprocessors)
    end

    it "sets concurrent_processor_pool_size to CPU count" do
      expect(config.processor_config.concurrent_processor_pool_size).to eq(Etc.nprocessors)
    end

    it "sets batch_slow_threshold_ms to 5000" do
      expect(config.batch_slow_threshold_ms).to eq(5000)
    end
  end

  describe "logging defaults" do
    it "reads log_requests from env" do
      ENV["API_CLIENT_LOG_REQUESTS"] = "true"
      fresh = described_class.new
      expect(fresh.log_requests).to be true
    ensure
      ENV.delete("API_CLIENT_LOG_REQUESTS")
    end

    it "reads log_bodies from env" do
      ENV["API_CLIENT_LOG_BODIES"] = "1"
      fresh = described_class.new
      expect(fresh.log_bodies).to be true
    ensure
      ENV.delete("API_CLIENT_LOG_BODIES")
    end
  end

  describe ApiClient::CircuitConfig do
    subject(:circuit) { described_class.new }

    describe "#track_only" do
      it "sets tracked_errors" do
        circuit.track_only(Timeout::Error, Errno::ECONNREFUSED)
        expect(circuit.tracked_errors).to eq([Timeout::Error, Errno::ECONNREFUSED])
      end

      it "invalidates to_h cache" do
        circuit.to_h
        circuit.track_only(Timeout::Error)
        expect(circuit.to_h[:tracked_errors]).to eq(["Timeout::Error"])
      end
    end

    describe "#to_h" do
      it "includes all config keys" do
        expect(circuit.to_h)
          .to include(:threshold, :cool_off, :data_store, :window_size, :tracked_errors)
      end

      it "returns nil tracked_errors by default" do
        expect(circuit.to_h[:tracked_errors]).to be_nil
      end
    end
  end

  describe ApiClient::RetryConfig do
    subject(:retry_config) { described_class.new }

    describe "#to_h" do
      it "returns consistent hash" do
        first = retry_config.to_h
        expect(retry_config.to_h).to eq(first)
      end

      it "reflects changes when max changes" do
        retry_config.max = 5
        expect(retry_config.to_h[:max]).to eq(5)
      end

      it "clears retry_statuses when max is zero" do
        retry_config.max = 0
        expect(retry_config.to_h[:retry_statuses]).to eq([])
      end
    end
  end

  describe ApiClient::JwtConfig do
    subject(:jwt_config) { described_class.new }

    describe "#to_h" do
      subject(:hash) { jwt_config.to_h }

      it "includes algorithm" do
        expect(hash).to include(algorithm: "RS256")
      end

      it "includes jwks_ttl" do
        expect(hash).to include(jwks_ttl: 600)
      end

      it "includes token_lifetime" do
        expect(hash).to include(token_lifetime: 900)
      end

      it "includes allow_hmac" do
        expect(hash).to include(allow_hmac: false)
      end

      it "includes leeway" do
        expect(hash).to include(leeway: 30)
      end
    end
  end
end
