RSpec.shared_examples "request flow workflow" do
  describe "user -> posts request flow" do
    subject(:posts) do
      client.request_flow
        .fetch(:get, "/users/1")
        .then { |r| JSON.parse(r.body)["post_ids"] }
        .fan_out { |id| {method: :get, path: "/posts/#{id}"} }
        .map { |r| JSON.parse(r.body) }
        .collect
    end

    it "returns expected post count" do
      expect(posts.size).to eq(3)
    end

    it "includes required fields" do
      expect(posts).to all(include("id", "title", "body"))
    end
  end
end
