require "spec_helper"

RSpec.describe ApiClient::Examples::ThreatScanner do
  it_behaves_like "canonical request flow example" do
    let(:example_class) { described_class }
    let(:invoke_method) { ->(c) { c.scan(indicator_id: "IOC-8842") } }
    let(:initial_path_pattern) { %r{/threats/indicators/IOC-8842/feeds$} }
    let(:initial_response_body) { '{"feed_ids":["F-1","F-2","F-3"]}' }
    let(:id_key) { "feed_ids" }
    let(:fan_out_path_pattern) { %r{/feeds/F-\d+/check$} }
    let(:fan_out_response_body) { '{"hash":"abc123","matched":true}' }
  end

  it "uses concurrent backend" do
    expect(described_class::ADAPTER).to eq(:concurrent)
  end

  it "uses ractor processor" do
    expect(described_class::PROCESSOR).to eq(:ractor)
  end
end
