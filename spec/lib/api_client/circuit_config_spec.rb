require "spec_helper"
require "api_client"

RSpec.describe ApiClient::CircuitConfig do
  subject(:config) { described_class.new }

  describe "default values" do
    it "sets threshold to 5" do
      expect(config.threshold).to eq(5)
    end

    it "sets cool_off to 30" do
      expect(config.cool_off).to eq(30)
    end

    it "sets data_store to :memory" do
      expect(config.data_store).to eq(:memory)
    end

    it "sets redis_pool to nil" do
      expect(config.redis_pool).to be_nil
    end

    it "sets redis_client to nil" do
      expect(config.redis_client).to be_nil
    end
  end

  describe "#to_h" do
    it "returns hash with settings" do
      expect(config.to_h).to include(:threshold, :cool_off, :data_store)
    end
  end
end
