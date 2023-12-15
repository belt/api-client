require "spec_helper"
require "api_client"

RSpec.describe ApiClient::Error do
  it "inherits from StandardError" do
    expect(described_class.superclass).to eq(StandardError)
  end
end
