require "spec_helper"

RSpec.describe ApiClient::Examples::MetricsCollector do
  it_behaves_like "canonical request flow example" do
    let(:example_class) { described_class }
    let(:invoke_method) { ->(c) { c.collect_metrics(namespace: "production") } }
    let(:initial_path_pattern) { %r{/metrics/namespaces/production/sources$} }
    let(:initial_response_body) { '{"source_ids":["cpu","memory","disk"]}' }
    let(:id_key) { "source_ids" }
    let(:fan_out_path_pattern) { %r{/sources/\w+/latest$} }
    let(:fan_out_response_body) { '{"value":42.5,"unit":"percent"}' }
  end

  it "uses sequential adapter" do
    expect(described_class::ADAPTER).to eq(:sequential)
  end

  it "uses concurrent processor" do
    expect(described_class::PROCESSOR).to eq(:concurrent)
  end
end
