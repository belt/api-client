require "spec_helper"

RSpec.describe ApiClient::Examples::PayReconciler do
  it_behaves_like "canonical request flow example" do
    let(:example_class) { described_class }
    let(:invoke_method) { ->(c) { c.reconcile(batch_id: "BATCH-2024-01") } }
    let(:initial_path_pattern) { %r{/payments/batches/BATCH-2024-01/gateways$} }
    let(:initial_response_body) { '{"gateway_ids":["stripe","braintree"]}' }
    let(:id_key) { "gateway_ids" }
    let(:fan_out_path_pattern) { %r{/gateways/\w+/settlements$} }
    let(:fan_out_response_body) { '{"transactions":[{"id":"TXN-1","amount":100}]}' }
  end

  it "uses concurrent adapter" do
    expect(described_class::ADAPTER).to eq(:concurrent)
  end

  it "uses concurrent processor" do
    expect(described_class::PROCESSOR).to eq(:concurrent)
  end
end
