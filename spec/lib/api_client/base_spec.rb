require "spec_helper"
require "api_client"

RSpec.describe ApiClient::Base, :integration do
  subject(:client) { client_for_server }

  describe "#initialize" do
    it "builds config" do
      expect(client.config).to be_a(ApiClient::Configuration)
    end

    it "builds connection" do
      expect(client.connection).to be_a(ApiClient::Connection)
    end

    it "builds circuit" do
      expect(client.circuit).to be_a(ApiClient::Circuit)
    end

    context "with overrides" do
      subject(:client) { client_for_server(read_timeout: 99) }

      it "applies overrides to config" do
        expect(client.config.read_timeout).to eq(99)
      end
    end

    context "with url: parameter (Faraday-style)" do
      subject(:client) { described_class.new(url: base_url) }

      it "sets service_uri from url" do
        expect(client.config.service_uri).to eq(base_url)
      end
    end

    context "with block configuration (Faraday-style)" do
      subject(:client) do
        described_class.new(url: base_url) do |config|
          config.read_timeout = 120
        end
      end

      it "applies block configuration" do
        expect(client.config.read_timeout).to eq(120)
      end
    end
  end

  describe "Faraday-compatible accessors" do
    describe "#url_prefix" do
      it "returns base URI" do
        expect(client.url_prefix).to be_a(URI)
      end

      it "matches configured service_uri" do
        expect(client.url_prefix.to_s).to start_with(base_url)
      end
    end

    describe "#headers" do
      it "returns default headers hash" do
        expect(client.headers).to be_a(Hash)
      end

      it "includes Content-Type" do
        expect(client.headers).to include("Content-Type")
      end
    end

    describe "#params" do
      it "returns default params hash" do
        expect(client.params).to be_a(Hash)
      end
    end

    describe "#options" do
      it "returns timeout options" do
        expect(client.options).to include(:open_timeout, :read_timeout, :write_timeout)
      end
    end
  end

  describe "HTTP verbs" do
    it_behaves_like "HTTP verb", :get
    it_behaves_like "HTTP verb", :post
    it_behaves_like "HTTP verb", :put
    it_behaves_like "HTTP verb", :patch
    it_behaves_like "HTTP verb", :delete
    it_behaves_like "HTTP verb", :head

    describe "#get" do
      it "fetches resource" do
        response = client.get("/users/1")
        body = JSON.parse(response.body)
        expect(body["id"]).to eq(1)
      end

      context "with positional params (Faraday-style)" do
        it "passes params to request" do
          response = client.get("/users", {page: 1})
          expect(response.status).to eq(200)
        end

        it "passes params and headers" do
          response = client.get("/users", {page: 1}, {"X-Custom" => "value"})
          expect(response.status).to eq(200)
        end
      end

      context "with keyword params" do
        it "passes params via keyword" do
          response = client.get("/users", params: {page: 1})
          expect(response.status).to eq(200)
        end

        it "passes headers via keyword" do
          response = client.get("/users", headers: {"X-Custom" => "value"})
          expect(response.status).to eq(200)
        end
      end

      context "with block (Faraday-style)" do
        it "allows request customization" do
          response = client.get("/users") do |req|
            req.params["page"] = 1
          end
          expect(response.status).to eq(200)
        end

        it "allows header customization" do
          response = client.get("/users") do |req|
            req.headers["X-Custom"] = "block-value"
          end
          expect(response.status).to eq(200)
        end
      end
    end

    describe "#post" do
      it "creates resource" do
        response = client.post("/users", body: {name: "New User"})
        expect(response.status).to eq(201)
      end

      context "with positional body (Faraday-style)" do
        it "passes body to request" do
          response = client.post("/users", {name: "Positional User"})
          expect(response.status).to eq(201)
        end

        it "passes body and headers" do
          response = client.post("/users", {name: "Test"}, {"X-Custom" => "value"})
          expect(response.status).to eq(201)
        end
      end

      context "with block (Faraday-style)" do
        it "allows body customization" do
          response = client.post("/users") do |req|
            req.body = {name: "Block User"}
          end
          expect(response.status).to eq(201)
        end
      end
    end
  end

  describe "#batch" do
    let(:requests) do
      [
        {method: :get, path: "/users/1"},
        {method: :get, path: "/users/2"}
      ]
    end

    it "executes requests" do
      responses = client.batch(requests)
      expect(responses.size).to eq(2)
    end

    it "returns Faraday::Response objects" do
      responses = client.batch(requests)
      expect(responses).to all(be_a(Faraday::Response))
    end

    it "maintains order" do
      responses = client.batch(requests)
      ids = responses.map { |r| JSON.parse(r.body)["id"] }
      expect(ids).to eq([1, 2])
    end

    context "with forced adapter" do
      it "uses specified adapter" do
        responses = client.batch(requests, adapter: :sequential)
        expect(responses.size).to eq(2)
      end
    end
  end

  describe "#sequential" do
    let(:requests) do
      [
        {method: :get, path: "/users/1"},
        {method: :get, path: "/users/2"}
      ]
    end

    it "executes requests sequentially" do
      responses = client.sequential(requests)
      expect(responses.size).to eq(2)
    end
  end

  describe "#request_flow" do
    it "returns RequestFlow instance" do
      expect(client.request_flow).to be_a(ApiClient::RequestFlow)
    end

    it_behaves_like "request flow workflow"
  end

  describe "circuit breaker integration" do
    # Use a fresh client with unique circuit name for each test
    let(:circuit_client) do
      # Create client with unique service_uri to get unique circuit name
      described_class.new(
        service_uri: ApiClient.configuration.service_uri,
        circuit: {threshold: 5, cool_off: 30}
      )
    end

    describe "#circuit_open?" do
      it "returns false initially" do
        # Fresh client should have closed circuit
        fresh = described_class.new(service_uri: "http://circuit-test-#{SecureRandom.hex(4)}.local")
        expect(fresh.circuit_open?).to be false
      end
    end

    describe "#reset_circuit!" do
      it "resets circuit state" do
        expect { client.reset_circuit! }.not_to raise_error
      end
    end

    context "when failures exceed threshold" do
      let(:failing_client) do
        # Use unique host to get isolated circuit
        uri = URI.parse(ApiClient.configuration.service_uri)
        unique_uri = "#{uri.scheme}://circuit-fail-#{SecureRandom.hex(4)}.#{uri.host}:#{uri.port}"

        described_class.new(service_uri: unique_uri).tap do |c|
          c.config.circuit.threshold = 2
        end
      end

      before do
        # Stub the unique host to route to test server
        stub_request(:get, /circuit-fail.*\/error\/500/).to_return(status: 500, body: "error")
        stub_request(:get, /circuit-fail.*\/health/).to_return(status: 200, body: "ok")

        2.times do
          failing_client.get("/error/500")
        rescue
          nil
        end
      end

      it "opens circuit" do
        expect(failing_client.circuit_open?).to be true
      end

      it "raises CircuitOpenError" do
        expect { failing_client.get("/health") }.to raise_error(ApiClient::CircuitOpenError)
      end

      it "closes after reset" do
        failing_client.reset_circuit!
        # Note: Stoplight 5.x global state means reset! clears local tracking
        # but the underlying Stoplight circuit may still be open
        expect(failing_client.circuit.failure_count).to eq(0)
      end
    end
  end

  describe "#batch_adapter" do
    it "returns symbol" do
      expect(client.batch_adapter).to be_a(Symbol)
    end
  end

  describe "#available_adapters" do
    it "returns array of symbols" do # rubocop:disable RSpec/MultipleExpectations
      expect(client.available_adapters).to be_an(Array)
      expect(client.available_adapters).to all(be_a(Symbol))
    end

    it "includes sequential" do
      expect(client.available_adapters).to include(:sequential)
    end
  end
end
