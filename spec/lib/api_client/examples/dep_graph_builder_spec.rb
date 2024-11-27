require "spec_helper"

RSpec.describe ApiClient::Examples::DepGraphBuilder do
  it_behaves_like "canonical request flow example" do
    let(:example_class) { described_class }
    let(:invoke_method) { ->(c) { c.build_graph(package: "api_client") } }
    let(:initial_path_pattern) { %r{/registry/packages/api_client/dependencies$} }
    let(:initial_response_body) { '{"dep_names":["faraday","concurrent-ruby"]}' }
    let(:id_key) { "dep_names" }
    let(:fan_out_path_pattern) { %r{/packages/[\w-]+/metadata$} }
    let(:fan_out_response_body) { '{"name":"faraday","version":"2.9.0"}' }
  end

  it "uses concurrent adapter" do
    expect(described_class::ADAPTER).to eq(:concurrent)
  end

  it "uses sequential processor" do
    expect(described_class::PROCESSOR).to eq(:sequential)
  end
end
