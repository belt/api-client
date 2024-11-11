require "spec_helper"

RSpec.describe ApiClient::Examples::ComplianceAuditor do
  it_behaves_like "canonical request flow example" do
    let(:example_class) { described_class }
    let(:invoke_method) { ->(c) { c.build_report(tenant_id: "T-100") } }
    let(:initial_path_pattern) { %r{/compliance/tenants/T-100/audit-sources$} }
    let(:initial_response_body) { '{"source_ids":["S-1","S-2","S-3"]}' }
    let(:id_key) { "source_ids" }
    let(:fan_out_path_pattern) { %r{/audit/S-\d+/entries$} }
    let(:fan_out_response_body) { '{"entries":[{"action":"login","ts":1700000000}]}' }
  end

  it "uses typhoeus adapter" do
    expect(described_class::ADAPTER).to eq(:typhoeus)
  end

  it "uses concurrent processor" do
    expect(described_class::PROCESSOR).to eq(:concurrent)
  end
end
