require "spec_helper"

RSpec.describe ApiClient::Examples::NotifyDispatcher do
  it_behaves_like "canonical request flow example" do
    let(:example_class) { described_class }
    let(:invoke_method) { ->(c) { c.dispatch(campaign_id: "CAMP-77") } }
    let(:initial_path_pattern) { %r{/notifications/campaigns/CAMP-77/recipients$} }
    let(:initial_response_body) { '{"recipient_ids":["R-1","R-2"]}' }
    let(:id_key) { "recipient_ids" }
    let(:fan_out_path_pattern) { %r{/deliver/R-\d+$} }
    let(:fan_out_response_body) { '{"delivered":true,"channel":"email"}' }
  end

  it "uses async adapter" do
    expect(described_class::ADAPTER).to eq(:async)
  end

  it "uses concurrent processor" do
    expect(described_class::PROCESSOR).to eq(:concurrent)
  end
end
