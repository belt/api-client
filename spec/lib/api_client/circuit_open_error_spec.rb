require "spec_helper"
require "api_client"

RSpec.describe ApiClient::CircuitOpenError do
  subject(:error) { described_class.new("payment-api") }

  it "inherits from ApiClient::Error" do
    expect(described_class.superclass).to eq(ApiClient::Error)
  end

  describe "#service" do
    it "returns the service name" do
      expect(error.service).to eq("payment-api")
    end
  end

  describe "#message" do
    it "includes service name" do
      expect(error.message).to include("payment-api")
    end

    context "with custom message" do
      subject(:error) { described_class.new("api", "Custom message") }

      it "uses custom message" do
        expect(error.message).to eq("Custom message")
      end
    end
  end
end
