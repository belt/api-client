require "spec_helper"
require "api_client"

RSpec.describe ApiClient::Base, :integration do # rubocop:disable RSpec/SpecFilePathFormat
  subject(:client) { client_for_server }

  describe "end-to-end workflows" do
    describe "sequential and batch requests" do
      let(:user_response) { client_for_server(read_timeout: 10).get("/users/1") }
      let(:user) { JSON.parse(user_response.body) }
      let(:post_responses) do
        requests = user["post_ids"].map { |id| {method: :get, path: "/posts/#{id}"} }
        client.batch(requests)
      end

      it "fetches user with 200 status" do
        expect(user_response.status).to eq(200)
      end

      it "returns correct user id" do
        expect(user["id"]).to eq(1)
      end

      it "fetches posts with 200 status" do
        expect(post_responses).to all(have_attributes(status: 200))
      end

      it "returns posts matching user post_ids" do
        expect(post_responses.map { |r| JSON.parse(r.body)["id"] }).to eq(user["post_ids"])
      end
    end

    describe "request flow workflow" do
      subject(:client) { client_for_server }

      it_behaves_like "request flow workflow"
    end

    describe "circuit breaker lifecycle" do
      # Use a method instead of let to ensure fresh ID per example
      def fresh_circuit_client
        ApiClient::TestClient.new(
          service_uri: base_url,
          test_id: SecureRandom.hex(8),
          circuit: {threshold: 3, cool_off: 1}
        ).tap(&:reset_circuit!)
      end

      it "starts closed" do
        expect(fresh_circuit_client.circuit_open?).to be false
      end

      it "opens after threshold failures" do
        client = fresh_circuit_client
        3.times { client.get("/error/500") rescue nil } # rubocop:disable Style/RescueModifier
        expect(client.circuit_open?).to be true
      end

      it "fails fast when open" do
        client = fresh_circuit_client
        3.times { client.get("/error/500") rescue nil } # rubocop:disable Style/RescueModifier
        expect { client.get("/health") }.to raise_error(ApiClient::CircuitOpenError)
      end

      it "closes after reset" do
        client = fresh_circuit_client
        3.times { client.get("/error/500") rescue nil } # rubocop:disable Style/RescueModifier
        client.reset_circuit!
        expect(client.circuit_open?).to be false
      end
    end

    describe "request lifecycle hooks" do
      let(:events) { [] }

      before do
        ApiClient.configure do |config|
          config.on(:request_start) { |p| events << [:start, p[:method]] }
          config.on(:request_complete) { |p| events << [:complete, p[:status]] }
        end
      end

      it "fires start and complete events" do
        client.get("/health")

        expect(events).to include([:start, :get], [:complete, 200])
      end
    end
  end

  describe "error scenarios" do
    it "raises on connection failure" do
      bad_client = described_class.new(service_uri: "http://localhost:1")
      expect { bad_client.get("/health") }.to raise_error(Faraday::ConnectionFailed)
    end

    it "raises on timeout" do
      slow_client = client_for_server(adapter: :net_http, read_timeout: 0.05, retry: {max: 0})
      expect { slow_client.get("/delay/1", params: {_t: Time.now.to_f}) }
        .to raise_error(Faraday::TimeoutError)
    end

    describe "HTTP error responses" do
      subject(:no_retry_client) { client_for_server(retry: {max: 0}) }

      it "returns 404 for not found" do
        expect(no_retry_client.get("/error/404").status).to eq(404)
      end

      it "returns 500 for server error" do
        expect(no_retry_client.get("/error/500").status).to eq(500)
      end
    end
  end

  describe "adapter detection" do
    it "includes sequential adapter" do
      expect(client.available_adapters).to include(:sequential)
    end

    it "selects from known adapters" do
      expect(ApiClient::Backend::Registry::CORE_BACKENDS).to include(client.batch_adapter)
    end
  end
end
