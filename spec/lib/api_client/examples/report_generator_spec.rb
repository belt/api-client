require "spec_helper"

RSpec.describe ApiClient::Examples::ReportGenerator do
  it_behaves_like "canonical request flow example" do
    let(:example_class) { described_class }
    let(:invoke_method) { ->(c) { c.generate(report_type: "monthly-summary") } }
    let(:initial_path_pattern) { %r{/reports/monthly-summary/sections$} }
    let(:initial_response_body) { '{"section_ids":["overview","details","appendix"]}' }
    let(:id_key) { "section_ids" }
    let(:fan_out_path_pattern) { %r{/monthly-summary/sections/\w+$} }
    let(:fan_out_response_body) { '{"content":"Section data here"}' }
  end

  it "uses sequential adapter" do
    expect(described_class::ADAPTER).to eq(:sequential)
  end

  it "uses sequential processor" do
    expect(described_class::PROCESSOR).to eq(:sequential)
  end
end
