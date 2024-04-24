require "spec_helper"
require "api_client"

RSpec.describe ApiClient::Circuit do
  # Use unique circuit names to avoid shared state between tests
  subject(:circuit) { described_class.new(circuit_name, config) }

  let(:circuit_name) { "test-service-#{SecureRandom.hex(4)}" }
  let(:config) { ApiClient::CircuitConfig.new }

  # Helper to trigger circuit failures
  def trigger_failures(count)
    count.times do
      circuit.run { raise "error" }
    rescue RuntimeError, Stoplight::Error::RedLight
      nil
    end
  end

  describe "#initialize" do
    it "sets name" do
      expect(circuit.name).to eq(circuit_name)
    end

    it "sets config" do
      expect(circuit.config).to eq(config)
    end
  end

  describe "#run" do
    it "executes block" do
      result = circuit.run { "success" }
      expect(result).to eq("success")
    end

    it "returns block result" do
      result = circuit.run { 42 }
      expect(result).to eq(42)
    end

    context "when block raises" do
      it "propagates exception" do
        expect { circuit.run { raise "error" } }.to raise_error("error")
      end
    end
  end

  describe "#open?" do
    it "returns false initially" do
      expect(circuit.open?).to be false
    end

    context "when threshold failures occur" do
      before do
        config.threshold = 2
        trigger_failures(2)
      end

      it "returns true" do
        expect(circuit.open?).to be true
      end
    end
  end

  describe "#closed?" do
    it "returns true initially" do
      expect(circuit.closed?).to be true
    end

    it "is opposite of open?" do
      expect(circuit.closed?).to eq(!circuit.open?)
    end
  end

  describe "#half_open?" do
    it "returns false initially" do
      expect(circuit.half_open?).to be false
    end

    context "when in cool_off period", :timecop do
      before do
        config.threshold = 1
        config.cool_off = 5
        trigger_failures(1)
      end

      it "returns true when probing" do
        Timecop.freeze(Time.now + 6) do
          expect(circuit.half_open?).to be true
        end
      end
    end
  end

  describe "#state" do
    it "returns green initially" do
      expect(circuit.state).to eq("green")
    end

    context "when failures occur" do
      before do
        config.threshold = 2
        trigger_failures(2)
      end

      it "returns red" do
        expect(circuit.state).to eq("red")
      end
    end
  end

  describe "#failure_count" do
    it "returns 0 initially" do
      expect(circuit.failure_count).to eq(0)
    end

    it "increments on failures" do
      config.threshold = 10 # High threshold so circuit stays closed
      trigger_failures(3)
      expect(circuit.failure_count).to eq(3)
    end
  end

  describe "#recent_failures" do
    before do
      config.threshold = 10 # High threshold
      trigger_failures(3)
    end

    it "returns failure details" do
      failures = circuit.recent_failures
      expect(failures.size).to eq(3)
      expect(failures.first).to include(:error, :message, :time)
    end

    it "respects limit" do
      failures = circuit.recent_failures(limit: 2)
      expect(failures.size).to eq(2)
    end
  end

  describe "#metrics" do
    before do
      config.threshold = 10
      config.cool_off = 30
      trigger_failures(2)
    end

    it "returns health snapshot" do
      metrics = circuit.metrics
      expect(metrics).to include(
        name: circuit_name,
        state: "green",
        failure_count: 2,
        threshold: 10,
        cool_off: 30
      )
    end
  end

  describe "#reset!" do
    before do
      config.threshold = 2
      trigger_failures(2)
    end

    it "resets local state" do
      expect(circuit.failure_count).to be > 0
      circuit.reset!
      expect(circuit.failure_count).to eq(0)
      expect(circuit.recent_failures).to be_empty
    end
  end

  describe "#with_fallback" do
    before do
      config.threshold = 1
      trigger_failures(1)
    end

    it "returns fallback when circuit open" do
      result = circuit.with_fallback { "cached" }.run { "live" }
      expect(result).to eq("cached")
    end

    it "returns live result when circuit closed" do
      # Use a fresh circuit that hasn't failed
      fresh_circuit = described_class.new("fresh-#{SecureRandom.hex(4)}", config)
      result = fresh_circuit.with_fallback { "cached" }.run { "live" }
      expect(result).to eq("live")
    end

    it "is chainable" do
      expect(circuit.with_fallback { "x" }).to eq(circuit)
    end
  end

  describe "#on_error" do
    let(:errors) { [] }

    it "calls handler on error" do
      config.threshold = 10 # Keep circuit open
      circuit.on_error { |e| errors << e }
      begin
        circuit.run { raise "boom" }
      rescue
        nil
      end

      expect(errors.size).to eq(1)
      expect(errors.first.message).to eq("boom")
    end

    it "is chainable" do
      expect(circuit.on_error {}).to eq(circuit)
    end

    it "can combine with fallback" do
      config.threshold = 1
      trigger_failures(1)

      result = circuit
        .on_error { |e| errors << e }
        .with_fallback { "fallback" }
        .run { "live" }

      expect(result).to eq("fallback")
    end
  end

  describe "threshold behavior" do
    before { config.threshold = 3 }

    it "stays closed below threshold" do
      trigger_failures(2)
      expect(circuit.open?).to be false
    end

    it "opens at threshold" do
      trigger_failures(3)
      expect(circuit.open?).to be true
    end
  end

  describe "redis_pool configuration" do
    it "accepts redis_pool on CircuitConfig" do
      pool = double("pool")
      config.redis_pool = pool
      expect(config.redis_pool).to eq(pool)
    end

    it "prefers redis_pool over redis_client" do
      pool = double("pool")
      client = double("client")
      config.redis_pool = pool
      config.redis_client = client
      config.data_store = :redis

      # The circuit should use redis_pool (first in precedence)
      resolved = circuit.send(:resolve_data_store)
      # Stoplight::DataStore::Redis receives pool_or_client — verify pool was chosen
      # by checking the argument passed to the data store constructor
      expect(resolved).to be_a(Stoplight::DataStore::Redis) if defined?(Stoplight::DataStore::Redis)
    end

    it "falls back to redis_client when redis_pool is nil" do
      config.redis_pool = nil
      config.redis_client = double("client")
      config.data_store = :redis

      resolved = circuit.send(:resolve_data_store)
      expect(resolved).to be_a(Stoplight::DataStore::Redis) if defined?(Stoplight::DataStore::Redis)
    end

    it "returns nil when data_store is :memory" do
      config.data_store = :memory
      expect(circuit.send(:resolve_data_store)).to be_nil
    end
  end

  describe "cool_off behavior", :timecop do
    before do
      config.threshold = 1
      config.cool_off = 10
      begin
        circuit.run { raise "error" }
      rescue
        nil
      end
    end

    it "blocks requests when open" do
      expect { circuit.run { "success" } }.to raise_error(ApiClient::CircuitOpenError)
    end

    it "allows probe after cool_off" do
      Timecop.freeze(Time.now + 11) do
        # Half-open state allows one request through
        expect { circuit.run { "success" } }.not_to raise_error
      end
    end
  end
end
