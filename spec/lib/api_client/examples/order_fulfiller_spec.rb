require "spec_helper"

RSpec.describe ApiClient::Examples::OrderFulfiller do
  it_behaves_like "canonical request flow example" do
    let(:example_class) { described_class }
    let(:invoke_method) { ->(c) { c.fulfill_orders(order_id: "ORD-9001") } }
    let(:initial_path_pattern) { %r{/orders/ORD-9001$} }
    let(:initial_response_body) { '{"line_item_ids":["LI-1","LI-2","LI-3"]}' }
    let(:id_key) { "line_item_ids" }
    let(:fan_out_path_pattern) { %r{/inventory/LI-\d+$} }
    let(:fan_out_response_body) { '{"sku":"SKU-100","qty":5}' }
  end

  it "uses typhoeus adapter" do
    expect(described_class::ADAPTER).to eq(:typhoeus)
  end

  it "uses ractor processor" do
    expect(described_class::PROCESSOR).to eq(:ractor)
  end
end
