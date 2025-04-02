require "spec_helper"
require "api_client"

RSpec.describe ApiClient::NullCircuit do
  subject(:circuit) { described_class.new("test-service") }

  describe "pass-through behavior" do
    it "always executes the block" do
      result = circuit.run { 42 }
      expect(result).to eq(42)
    end

    it "propagates exceptions from the block" do
      expect { circuit.run { raise "boom" } }.to raise_error(RuntimeError, "boom")
    end

    it "is never open" do
      expect(circuit.open?).to be false
    end

    it "is always closed" do
      expect(circuit.closed?).to be true
    end

    it "is never half-open" do
      expect(circuit.half_open?).to be false
    end

    it "state is always green" do
      expect(circuit.state).to eq("green")
    end

    it "failure_count is always 0" do
      expect(circuit.failure_count).to eq(0)
    end

    it "recent_failures is always empty" do
      expect(circuit.recent_failures).to eq([])
      expect(circuit.recent_failures(limit: 100)).to eq([])
    end

    it "metrics shows disabled" do
      metrics = circuit.metrics
      expect(metrics[:enabled]).to be false
      expect(metrics[:name]).to eq("test-service")
      expect(metrics[:state]).to eq("green")
    end

    it "reset! is a no-op" do
      expect { circuit.reset! }.not_to raise_error
    end

    it "with_fallback returns self for chaining" do
      expect(circuit.with_fallback { "fallback" }).to eq(circuit)
    end

    it "on_error returns self for chaining" do
      expect(circuit.on_error { |e| e }).to eq(circuit)
    end
  end

  describe "CircuitInterface compliance" do
    it "includes CircuitInterface" do
      expect(circuit).to be_a(ApiClient::CircuitInterface)
    end

    it "Circuit also includes CircuitInterface" do
      real_circuit = ApiClient::Circuit.new("real-test", ApiClient::CircuitConfig.new)
      expect(real_circuit).to be_a(ApiClient::CircuitInterface)
    end
  end
end
