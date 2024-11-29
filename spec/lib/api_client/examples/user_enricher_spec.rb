require "spec_helper"

RSpec.describe ApiClient::Examples::UserEnricher do
  it_behaves_like "canonical request flow example" do
    let(:example_class) { described_class }
    let(:invoke_method) { ->(c) { c.enrich(segment_id: "SEG-500") } }
    let(:initial_path_pattern) { %r{/users/segments/SEG-500/members$} }
    let(:initial_response_body) { '{"user_ids":["U-1","U-2","U-3"]}' }
    let(:id_key) { "user_ids" }
    let(:fan_out_path_pattern) { %r{/profiles/U-\d+$} }
    let(:fan_out_response_body) { '{"name":"Jane Doe","email":"[email]"}' }
  end

  it "uses sequential adapter" do
    expect(described_class::ADAPTER).to eq(:sequential)
  end

  it "uses ractor processor" do
    expect(described_class::PROCESSOR).to eq(:ractor)
  end
end
