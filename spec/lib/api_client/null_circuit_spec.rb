require "spec_helper"
require "api_client"

RSpec.describe ApiClient::NullCircuit do
  subject(:circuit) { described_class.new("test-service") }

  describe "#initialize" do
    it "stores name" do
      expect(circuit.name).to eq("test-service")
    end

    it "accepts optional config" do
      config = double("config")
      circuit_with_config = described_class.new("service", config)
      expect(circuit_with_config.config).to eq(config)
    end
  end

  describe "#run" do
    it "executes block directly" do
      result = circuit.run { 42 }
      expect(result).to eq(42)
    end

    it "propagates exceptions" do
      expect { circuit.run { raise "boom" } }.to raise_error(RuntimeError, "boom")
    end
  end

  describe "#with_fallback" do
    it "returns self for chaining" do
      ApiClient.configure { |c| c.logger = Logger.new(File::NULL) }
      expect(circuit.with_fallback { "fallback" }).to be(circuit)
    end
  end

  describe "#on_error" do
    it "returns self for chaining" do
      expect(circuit.on_error { |e| puts e }).to be(circuit)
    end
  end

  describe "state methods" do
    it "#open? returns false" do
      expect(circuit.open?).to be false
    end

    it "#closed? returns true" do
      expect(circuit.closed?).to be true
    end

    it "#half_open? returns false" do
      expect(circuit.half_open?).to be false
    end

    it "#state returns green" do
      expect(circuit.state).to eq("green")
    end
  end

  describe "#failure_count" do
    it "returns 0" do
      expect(circuit.failure_count).to eq(0)
    end
  end

  describe "#recent_failures" do
    it "returns empty array" do
      expect(circuit.recent_failures).to eq([])
    end

    it "ignores limit parameter" do
      expect(circuit.recent_failures(limit: 5)).to eq([])
    end
  end

  describe "#metrics" do
    it "returns disabled state metrics" do
      metrics = circuit.metrics
      expect(metrics).to include(
        name: "test-service",
        state: "green",
        failure_count: 0,
        threshold: nil,
        cool_off: nil,
        window_size: nil,
        enabled: false
      )
    end
  end
end
