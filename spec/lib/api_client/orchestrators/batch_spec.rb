require "spec_helper"
require "api_client"

RSpec.describe ApiClient::Orchestrators::Batch, :integration do
  subject(:executor) { described_class.new(config) }

  let(:config) { build(:api_client_configuration, service_uri: base_url) }

  describe "#initialize" do
    it "sets config" do
      expect(executor.config).to eq(config)
    end

    it "resolves adapter" do
      expect(executor.adapter).not_to be_nil
    end
  end

  describe "#adapter_name" do
    it "returns symbol" do
      expect(executor.adapter_name).to be_a(Symbol)
    end

    it "returns known adapter name" do
      known_adapters = %i[typhoeus async concurrent sequential]
      expect(known_adapters).to include(executor.adapter_name)
    end
  end

  it_behaves_like "executor execute behavior"

  describe "#execute" do
    it "executes faster than sequential for delayed requests" do
      delayed_requests = 3.times.map { {method: :get, path: "/delay/0.2"} }
      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      executor.execute(delayed_requests)
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
      expect(elapsed).to be < 0.5 # 3 x 0.2s batch should take ~0.2s, not 0.6s
    end

    context "with mixed success and failure" do
      let(:requests) do
        [
          {method: :get, path: "/users/1"},
          {method: :get, path: "/error/500"},
          {method: :get, path: "/users/2"}
        ]
      end

      it "preserves order with failures" do
        expect(executor.execute(requests).map(&:status)).to eq([200, 500, 200])
      end
    end
  end

  describe "forced adapter" do
    context "with adapter: :sequential" do
      subject(:executor) { described_class.new(config, adapter: :sequential) }

      it "uses sequential adapter" do
        expect(executor.adapter_name).to eq(:sequential)
      end
    end
  end
end
