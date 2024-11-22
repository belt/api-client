require "spec_helper"

RSpec.describe ApiClient::Examples::GeoResolver do
  it_behaves_like "canonical request flow example" do
    let(:example_class) { described_class }
    let(:invoke_method) { ->(c) { c.resolve(domain: "cdn.example.com") } }
    let(:initial_path_pattern) { %r{/routing/domains/cdn\.example\.com/edges$} }
    let(:initial_response_body) { '{"edge_ids":["edge-us","edge-eu"]}' }
    let(:id_key) { "edge_ids" }
    let(:fan_out_path_pattern) { %r{/edges/edge-\w+/probe$} }
    let(:fan_out_response_body) { '{"latency_ms":42,"region":"us-east-1"}' }
  end

  it "uses concurrent adapter" do
    expect(described_class::ADAPTER).to eq(:concurrent)
  end

  it "uses async processor" do
    expect(described_class::PROCESSOR).to eq(:async)
  end
end
