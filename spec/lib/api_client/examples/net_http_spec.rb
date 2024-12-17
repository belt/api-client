# frozen_string_literal: true

require "spec_helper"

# Net::HTTP backend integration tests verify request/response round-trips.
# rubocop:disable RSpec/ExampleLength, RSpec/MultipleExpectations
RSpec.describe ApiClient::Examples::NetHttp do
  describe "::Backend" do
    subject(:backend) { described_class::Backend.new(config) }

    let(:config) do
      ApiClient::Configuration.new.tap do |c|
        c.service_uri = "https://api.example.com"
        c.base_path = "/v1"
        c.open_timeout = 5
        c.read_timeout = 10
      end
    end

    describe "#execute" do
      let(:requests) do
        [
          {method: :get, path: "/users/1", headers: {}, params: {}, body: nil},
          {method: :post, path: "/users", headers: {"Content-Type" => "application/json"}, params: {}, body: {name: "Alice"}}
        ]
      end

      before do
        stub_request(:get, "https://api.example.com/v1/users/1")
          .to_return(status: 200, body: '{"id":1,"name":"Bob"}', headers: {"Content-Type" => "application/json"})

        stub_request(:post, "https://api.example.com/v1/users")
          .with(body: '{"name":"Alice"}')
          .to_return(status: 201, body: '{"id":2,"name":"Alice"}', headers: {"Content-Type" => "application/json"})
      end

      it "executes HTTP requests and returns Faraday::Response objects" do
        responses = backend.execute(requests)

        expect(responses).to all(be_a(Faraday::Response))
        expect(responses.size).to eq(2)

        expect(responses[0].status).to eq(200)
        expect(responses[0].body).to eq('{"id":1,"name":"Bob"}')

        expect(responses[1].status).to eq(201)
        expect(responses[1].body).to eq('{"id":2,"name":"Alice"}')
      end

      it "handles request errors gracefully" do
        stub_request(:get, "https://api.example.com/v1/users/999")
          .to_raise(SocketError.new("Failed to open TCP connection"))

        error_requests = [{method: :get, path: "/users/999", headers: {}, params: {}, body: nil}]
        responses = backend.execute(error_requests)

        expect(responses.size).to eq(1)
        expect(responses[0]).to be_a(Faraday::Response)
        expect(responses[0].status).to eq(0)
        expect(responses[0].body).to include("Failed to open TCP connection")
      end

      it "merges default headers with request headers" do
        config.default_headers = {"X-API-Key" => "secret123"}

        stub_request(:get, "https://api.example.com/v1/users/1")
          .with(headers: {"X-API-Key" => "secret123", "X-Request-ID" => "abc"})
          .to_return(status: 200, body: "{}")

        requests = [{method: :get, path: "/users/1", headers: {"X-Request-ID" => "abc"}, params: {}, body: nil}]
        backend.execute(requests)

        expect(WebMock).to have_requested(:get, "https://api.example.com/v1/users/1")
          .with(headers: {"X-API-Key" => "secret123", "X-Request-ID" => "abc"})
      end

      it "handles query parameters" do
        stub_request(:get, "https://api.example.com/v1/users?page=2&limit=10")
          .to_return(status: 200, body: "[]")

        requests = [{method: :get, path: "/users", headers: {}, params: {page: 2, limit: 10}, body: nil}]
        responses = backend.execute(requests)

        expect(responses[0].status).to eq(200)
      end

      it "encodes JSON body for POST requests" do
        stub_request(:post, "https://api.example.com/v1/users")
          .with(body: '{"name":"Charlie","email":"charlie@example.com"}')
          .to_return(status: 201, body: "{}")

        requests = [{method: :post, path: "/users", headers: {}, params: {}, body: {name: "Charlie", email: "charlie@example.com"}}]
        backend.execute(requests)

        expect(WebMock).to have_requested(:post, "https://api.example.com/v1/users")
          .with(body: '{"name":"Charlie","email":"charlie@example.com"}')
      end
    end

    describe "#config" do
      it "returns the configuration" do
        expect(backend.config).to eq(config)
      end
    end
  end

  describe ".register!" do
    after do
      # Clean up registered backend
      ApiClient::Backend::Registry.instance_variable_set(:@custom_backends, nil)
      ApiClient::Backend::Registry.instance_variable_set(:@registry_items, ApiClient::Backend::Registry::CORE_BACKENDS.dup)
      ApiClient::Backend::Registry.instance_variable_set(:@available_cache, nil)
    end

    it "registers the Net::HTTP backend" do
      described_class.register!

      expect(ApiClient::Backend.available).to include(:net_http)
      expect(ApiClient::Backend.resolve(:net_http)).to eq(described_class::Backend)
    end

    it "allows using the backend with ApiClient::Base" do
      described_class.register!

      stub_request(:get, "https://api.example.com/users/1")
        .to_return(status: 200, body: '{"id":1}')

      client = ApiClient::Base.new(
        url: "https://api.example.com",
        adapter: :net_http,
        circuit: {enabled: false}
      )

      response = client.get("/users/1")
      expect(response.status).to eq(200)
      expect(response.body).to eq('{"id":1}')
    end
  end
end
# rubocop:enable RSpec/ExampleLength, RSpec/MultipleExpectations
