require "spec_helper"
require "api_client"

RSpec.describe ApiClient::RequestFlow, :integration do
  let(:client) { client_for_server }

  describe "request flow error recovery" do
    it "returns 404 response for missing paths" do
      result = client.request_flow
        .fetch(:get, "/nonexistent/path/that/404s")
        .then { |r| r.status }
        .collect

      expect(result).to eq(404)
    end

    it "handles transform exceptions" do
      expect {
        client.request_flow
          .fetch(:get, "/health")
          .then { |_r| raise "transform error" }
          .collect
      }.to raise_error(ApiClient::Error, /transform error/)
    end

    it "handles nil transform results" do
      result = client.request_flow
        .fetch(:get, "/health")
        .then { |_r| nil }
        .collect

      expect(result).to be_nil
    end
  end

  describe "fan-out resilience" do
    it "handles partial failures in fan-out" do
      responses = client.request_flow
        .fetch(:get, "/users/1")
        .then { [1, 999, 2] } # 999 might not exist but won't error
        .fan_out { |id| {method: :get, path: "/posts/#{id}"} }
        .collect

      expect(responses.size).to eq(3)
    end

    it "handles fan-out with error responses" do
      responses = client.request_flow
        .fetch(:get, "/users/1")
        .then { [200, 500, 404] }
        .fan_out { |status| {method: :get, path: "/error/#{status}"} }
        .collect

      expect(responses.map(&:status)).to eq([200, 500, 404])
    end

    it "handles very large fan-out" do
      responses = client.request_flow
        .fetch(:get, "/health")
        .then { (1..50).to_a }
        .fan_out { |id| {method: :get, path: "/posts/#{id}"} }
        .collect

      expect(responses.size).to eq(50)
    end
  end

  describe "chained operations resilience" do
    it "handles multiple transforms" do
      result = client.request_flow
        .fetch(:get, "/users/1")
        .then { |r| JSON.parse(r.body) }
        .then { |data| data["name"] }
        .then { |name| name.upcase }
        .then { |name| name.reverse }
        .collect

      expect(result).to be_a(String)
    end

    it "handles filter after fan-out" do
      result = client.request_flow
        .fetch(:get, "/users/1")
        .then { (1..10).to_a }
        .fan_out { |id| {method: :get, path: "/posts/#{id}"} }
        .filter { |r| r.status == 200 }
        .collect

      expect(result).to all(have_attributes(status: 200))
    end

    it "handles map after fan-out" do
      result = client.request_flow
        .fetch(:get, "/users/1")
        .then { [1, 2, 3] }
        .fan_out { |id| {method: :get, path: "/posts/#{id}"} }
        .map { |r| JSON.parse(r.body)["id"] }
        .collect

      expect(result).to eq([1, 2, 3])
    end
  end

  describe "request flow reset resilience" do
    it "clears all steps on reset" do
      request_flow = client.request_flow
        .fetch(:get, "/health")
        .then { |r| r.status }

      expect(request_flow.steps.size).to eq(2)

      request_flow.reset
      expect(request_flow.steps).to be_empty
    end

    it "allows new request flow after reset" do
      request_flow = client.request_flow
      request_flow.fetch(:get, "/error/500").then { |r| r.status }
      request_flow.reset

      result = request_flow
        .fetch(:get, "/health")
        .then { |r| r.status }
        .collect

      expect(result).to eq(200)
    end
  end

  describe "concurrent_map in request flow" do
    it "processes responses with concurrent_map" do
      unless ApiClient::Processing::ConcurrentProcessor.available?
        skip "concurrent-ruby not available"
      end

      result = client.request_flow
        .fetch(:get, "/users/1")
        .then { [1, 2, 3] }
        .fan_out { |id| {method: :get, path: "/posts/#{id}"} }
        .concurrent_map
        .collect

      expect(result.size).to eq(3)
      expect(result).to all(be_a(Hash))
    end
  end
end
