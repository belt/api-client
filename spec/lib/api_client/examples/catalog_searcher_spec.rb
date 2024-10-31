require "spec_helper"

RSpec.describe ApiClient::Examples::CatalogSearcher do
  it_behaves_like "canonical request flow example" do
    let(:example_class) { described_class }
    let(:invoke_method) { ->(c) { c.search(query: "ruby book") } }
    let(:initial_path_pattern) { %r{/catalog/providers$} }
    let(:initial_response_body) { '{"provider_ids":["P-1","P-2"]}' }
    let(:id_key) { "provider_ids" }
    let(:fan_out_path_pattern) { %r{/providers/P-\d+/search} }
    let(:fan_out_response_body) { '{"results":[{"title":"Ruby Programming"}]}' }
  end

  it "uses typhoeus adapter" do
    expect(described_class::ADAPTER).to eq(:typhoeus)
  end

  it "uses async processor" do
    expect(described_class::PROCESSOR).to eq(:async)
  end
end
