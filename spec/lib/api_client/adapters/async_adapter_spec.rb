require "spec_helper"
require "api_client"

# Load the adapter if available
if ApiClient::Backend.available?(:async)
  ApiClient::Backend.resolve(:async)
end

RSpec.describe ApiClient::Adapters::AsyncAdapter, :integration,
  if: ApiClient::Backend.available?(:async) do
  subject(:adapter) { described_class.new(config) }

  let(:config) { build(:api_client_configuration, service_uri: base_url) }

  it_behaves_like "parallel adapter"
  it_behaves_like "response normalization"

  describe "#initialize" do
    it "sets config" do
      expect(adapter.config).to eq(config)
    end
  end

  describe "error handling" do
    it "returns error response for failed requests" do
      responses = adapter.execute([{method: :get, path: "/error/500"}])
      expect(responses.first.status).to eq(500)
    end
  end
end
