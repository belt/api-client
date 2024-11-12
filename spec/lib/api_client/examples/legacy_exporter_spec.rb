require "spec_helper"

RSpec.describe ApiClient::Examples::LegacyExporter do
  it_behaves_like "canonical request flow example" do
    let(:example_class) { described_class }
    let(:invoke_method) { ->(c) { c.export(resource: "customers") } }
    let(:initial_path_pattern) { %r{/legacy/v1/customers/pages$} }
    let(:initial_response_body) { '{"page_ids":["PG-1","PG-2"]}' }
    let(:id_key) { "page_ids" }
    let(:fan_out_path_pattern) { %r{/legacy/v1/customers/pages/PG-\d+$} }
    let(:fan_out_response_body) { '{"records":[{"id":1,"name":"Acme Corp"}]}' }
  end

  it "uses typhoeus adapter" do
    expect(described_class::ADAPTER).to eq(:typhoeus)
  end

  it "uses sequential processor" do
    expect(described_class::PROCESSOR).to eq(:sequential)
  end
end
