RSpec.shared_examples "HTTP verb" do |verb|
  describe "##{verb}" do
    subject(:response) { client.public_send(verb, "/health") }

    it "returns a Faraday::Response" do
      expect(response).to be_a(Faraday::Response)
    end

    it "includes status code" do
      expect(response.status).to be_a(Integer)
    end

    it "includes response body" do
      expect(response.body).to be_a(String)
    end

    it "includes response headers" do
      expect(response.headers).to be_a(Hash)
    end
  end
end

RSpec.shared_examples "successful response" do
  it "returns 2xx status" do
    expect(response.status).to be_between(200, 299)
  end
end

RSpec.shared_examples "JSON response" do
  it "returns valid JSON" do
    expect { JSON.parse(response.body) }.not_to raise_error
  end
end
