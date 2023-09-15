RSpec.shared_examples "response normalization" do
  describe "response normalization" do
    it "returns Faraday::Response" do
      responses = adapter.execute([{method: :get, path: "/health"}])
      expect(responses.first).to be_a(Faraday::Response)
    end

    it "normalizes status code" do
      responses = adapter.execute([{method: :get, path: "/health"}])
      expect(responses.first.status).to eq(200)
    end

    it "normalizes headers" do
      responses = adapter.execute([{method: :get, path: "/health"}])
      expect(responses.first.headers).to be_a(Hash)
    end

    it "normalizes body" do
      responses = adapter.execute([{method: :get, path: "/health"}])
      expect(responses.first.body).to be_a(String)
    end
  end
end
