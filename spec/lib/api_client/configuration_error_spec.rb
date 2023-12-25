require "spec_helper"
require "api_client"

RSpec.describe ApiClient::ConfigurationError do
  it "inherits from ApiClient::Error" do
    expect(described_class.superclass).to eq(ApiClient::Error)
  end
end
