RSpec.shared_examples "concurrent adapter" do
  include_context "with executor requests"

  describe "#execute" do
    subject(:responses) { adapter.execute(requests) }

    let(:requests) { standard_requests }

    it "returns array of responses" do # rubocop:disable RSpec/MultipleExpectations
      expect(responses).to be_an(Array)
      expect(responses.size).to eq(3)
    end

    it "returns Faraday::Response objects" do
      expect(responses).to all(be_a(Faraday::Response))
    end

    it "maintains request order" do
      bodies = responses.map { |r| JSON.parse(r.body) }
      expect(bodies.map { |b| b["id"] }).to eq([1, 2, 3])
    end

    it "executes concurrently (timing)" do
      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      adapter.execute(requests)
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
      expect(elapsed).to be < 5.0
    end

    it "returns empty array for empty requests" do
      expect(adapter.execute([])).to eq([])
    end
  end
end

# Backward compatibility alias
RSpec.shared_examples "parallel adapter" do
  it_behaves_like "concurrent adapter"
end
