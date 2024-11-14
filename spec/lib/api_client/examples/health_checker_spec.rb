require "spec_helper"

RSpec.describe ApiClient::Examples::HealthChecker do
  it_behaves_like "canonical request flow example" do
    let(:example_class) { described_class }
    let(:invoke_method) { ->(c) { c.check(cluster: "us-east-1") } }
    let(:initial_path_pattern) { %r{/health/clusters/us-east-1/services$} }
    let(:initial_response_body) { '{"service_ids":["svc-a","svc-b","svc-c"]}' }
    let(:id_key) { "service_ids" }
    let(:fan_out_path_pattern) { %r{/services/svc-[a-c]/ping$} }
    let(:fan_out_response_body) { '{"status":"healthy","latency_ms":12}' }
  end

  it "uses async adapter" do
    expect(described_class::ADAPTER).to eq(:async)
  end

  it "uses async processor" do
    expect(described_class::PROCESSOR).to eq(:async)
  end
end
