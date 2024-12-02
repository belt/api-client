require "spec_helper"

RSpec.describe ApiClient::Examples::LogAggregator do
  it_behaves_like "canonical request flow example" do
    let(:example_class) { described_class }
    let(:invoke_method) { ->(c) { c.aggregate(service: "api-gateway", window: "1h") } }
    let(:initial_path_pattern) { %r{/logs/services/api-gateway/shards} }
    let(:initial_response_body) { '{"shard_ids":["SH-1","SH-2"]}' }
    let(:id_key) { "shard_ids" }
    let(:fan_out_path_pattern) { %r{/shards/SH-\d+/entries$} }
    let(:fan_out_response_body) { '{"entries":[{"level":"info","msg":"request handled"}]}' }
  end

  it "uses sequential adapter" do
    expect(described_class::ADAPTER).to eq(:sequential)
  end

  it "uses async processor" do
    expect(described_class::PROCESSOR).to eq(:async)
  end
end
