require "spec_helper"

RSpec.describe ApiClient::Examples::FeedIngestor do
  it_behaves_like "canonical request flow example" do
    let(:example_class) { described_class }
    let(:invoke_method) { ->(c) { c.ingest(feed_id: "FEED-42") } }
    let(:initial_path_pattern) { %r{/feeds/FEED-42/sources$} }
    let(:initial_response_body) { '{"source_urls":["/src/1","/src/2"]}' }
    let(:id_key) { "source_urls" }
    let(:fan_out_path_pattern) { %r{/src/\d+$} }
    let(:fan_out_response_body) { '{"entries":[{"text":"hello","ts":1700000000}]}' }
  end

  it "uses async adapter" do
    expect(described_class::ADAPTER).to eq(:async)
  end

  it "uses ractor processor" do
    expect(described_class::PROCESSOR).to eq(:ractor)
  end
end
