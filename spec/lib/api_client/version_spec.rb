require "spec_helper"
require "api_client/version"

RSpec.describe "ApiClient::VERSION" do
  subject(:version) { ApiClient::VERSION }

  it "is defined" do
    expect(version).not_to be_nil
  end

  it "is a string" do
    expect(version).to be_a(String)
  end

  it "follows semantic versioning format" do
    expect(version).to match(/\A\d+\.\d+\.\d+/)
  end
end
