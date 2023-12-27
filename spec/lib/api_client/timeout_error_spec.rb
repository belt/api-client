require "spec_helper"
require "api_client"

RSpec.describe ApiClient::TimeoutError do
  subject(:error) { described_class.new(:read) }

  it "inherits from ApiClient::Error" do
    expect(described_class.superclass).to eq(ApiClient::Error)
  end

  describe "#timeout_type" do
    it "returns the timeout type" do
      expect(error.timeout_type).to eq(:read)
    end
  end

  describe "#message" do
    it "includes timeout type" do
      expect(error.message).to include("read")
    end
  end
end
