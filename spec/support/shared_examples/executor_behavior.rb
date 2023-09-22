# Shared request definitions for executor specs
RSpec.shared_context "with executor requests" do
  let(:standard_requests) do
    [
      {method: :get, path: "/users/1"},
      {method: :get, path: "/users/2"},
      {method: :get, path: "/users/3"}
    ]
  end

  let(:mixed_requests) do
    [
      {method: :get, path: "/users/1"},
      {method: :get, path: "/error/500"},
      {method: :get, path: "/users/2"}
    ]
  end
end

# Shared examples for executor #execute behavior
RSpec.shared_examples "executor execute behavior" do
  include_context "with executor requests"

  describe "#execute" do
    subject(:responses) { executor.execute(requests) }

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

    context "with single request" do
      let(:requests) { [{method: :get, path: "/users/1"}] }

      it "returns single response" do
        expect(responses.size).to eq(1)
      end
    end

    it "returns empty array for empty requests" do
      expect(executor.execute([])).to eq([])
    end
  end
end
