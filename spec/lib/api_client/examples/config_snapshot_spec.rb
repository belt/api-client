require "spec_helper"

RSpec.describe ApiClient::Examples::ConfigSnapshot do
  it_behaves_like "canonical request flow example" do
    let(:example_class) { described_class }
    let(:invoke_method) { ->(c) { c.snapshot(app: "billing-service") } }
    let(:initial_path_pattern) { %r{/config/apps/billing-service/environments$} }
    let(:initial_response_body) { '{"environment_ids":["dev","staging","prod"]}' }
    let(:id_key) { "environment_ids" }
    let(:fan_out_path_pattern) { %r{/apps/billing-service/environments/\w+/snapshot$} }
    let(:fan_out_response_body) { '{"db_host":"db.local","cache_ttl":300}' }
  end

  it "uses async adapter" do
    expect(described_class::ADAPTER).to eq(:async)
  end

  it "uses sequential processor" do
    expect(described_class::PROCESSOR).to eq(:sequential)
  end
end
