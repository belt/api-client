require "spec_helper"
require "api_client"

RSpec.describe ApiClient::PoolConfig do
  subject(:config) { described_class.new }

  describe "default values" do
    it "sets size to CPU count" do
      expect(config.size).to eq(Etc.nprocessors)
    end

    it "sets timeout to 5" do
      expect(config.timeout).to eq(5)
    end

    it "sets enabled to true" do
      expect(config.enabled).to be true
    end
  end

  describe "#to_h" do
    it "returns hash with all settings" do
      expect(config.to_h).to eq(
        size: Etc.nprocessors,
        timeout: 5,
        enabled: true
      )
    end

    it "reflects mutations" do
      config.size = 20
      config.timeout = 10
      config.enabled = false
      expect(config.to_h).to eq(size: 20, timeout: 10, enabled: false)
    end
  end
end
