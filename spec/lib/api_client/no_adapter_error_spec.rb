require "spec_helper"
require "api_client"

RSpec.describe ApiClient::NoAdapterError do
  subject(:error) { described_class.new }

  it "inherits from ApiClient::Error" do
    expect(described_class.superclass).to eq(ApiClient::Error)
  end

  describe "#message" do
    it "suggests installing adapters" do
      expect(error.message).to include("typhoeus")
    end
  end
end
