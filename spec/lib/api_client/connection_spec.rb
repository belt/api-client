require "spec_helper"
require "api_client"

RSpec.describe ApiClient::Connection, :integration do
  subject(:connection) { described_class.new(config) }

  let(:config) { build(:api_client_configuration, service_uri: base_url) }

  describe "#initialize" do
    it "sets config" do
      expect(connection.config).to eq(config)
    end

    it "builds faraday connection" do
      connection.with_faraday do |f|
        expect(f).to be_a(Faraday::Connection)
      end
    end
  end

  describe "connection pooling" do
    context "with pooling enabled (default)" do
      it "uses ConnectionPool internally" do
        pool = connection.instance_variable_get(:@pool)
        expect(pool).to be_a(ConnectionPool)
      end

      it "returns Faraday::Connection from with_faraday" do
        connection.with_faraday do |f|
          expect(f).to be_a(Faraday::Connection)
        end
      end
    end

    context "with pooling disabled" do
      let(:config) do
        build(:api_client_configuration, service_uri: base_url).tap do |c|
          c.pool_config.enabled = false
        end
      end

      it "uses NullPool internally" do
        pool = connection.instance_variable_get(:@pool)
        expect(pool).to be_a(ApiClient::Concerns::NullPool)
      end

      it "still returns Faraday::Connection from with_faraday" do
        connection.with_faraday do |f|
          expect(f).to be_a(Faraday::Connection)
        end
      end

      it "still makes successful requests" do
        response = connection.get("/health")
        expect(response.status).to eq(200)
      end
    end
  end

  describe "#request" do
    it "returns Faraday::Response" do
      expect(connection.request(:get, "/health")).to be_a(Faraday::Response)
    end
  end

  describe "instrumentation" do
    let(:events) { [] }
    let(:subscriber) { nil }

    after { ApiClient::Hooks.unsubscribe(subscriber) if subscriber }

    context "with request_start hook" do
      let(:subscriber) do
        ApiClient::Hooks.subscribe(:request_start) { |*args| events << args }
      end

      before { subscriber }

      it "fires event" do
        connection.request(:get, "/health")
        expect(events).not_to be_empty
      end
    end

    context "with request_complete hook" do
      let(:subscriber) do
        ApiClient::Hooks.subscribe(:request_complete) do |*args|
          events << ActiveSupport::Notifications::Event.new(*args).payload
        end
      end

      before { subscriber }

      it "includes duration and status" do
        connection.request(:get, "/health")
        expect(events.first).to include(:duration, :status)
      end

      it "measures duration accurately" do
        connection.request(:get, "/delay/0.1", params: {_t: Time.now.to_f})
        expect(events.first[:duration]).to be >= 0.1
      end
    end
  end

  describe "HTTP verbs" do
    shared_examples "HTTP method" do |method|
      it "makes #{method.upcase} request" do
        response = connection.public_send(method, "/echo")
        expect(JSON.parse(response.body)["method"]).to eq(method.to_s.upcase)
      end
    end

    it_behaves_like "HTTP method", :get
    it_behaves_like "HTTP method", :post
    it_behaves_like "HTTP method", :put
    it_behaves_like "HTTP method", :patch
    it_behaves_like "HTTP method", :delete

    describe "#get" do
      it "passes params" do
        response = connection.get("/echo", params: {foo: "bar"})
        expect(response.status).to eq(200)
      end

      it "passes headers" do
        response = connection.get("/echo",
          headers: {"X-Custom" => "value"}, params: {_t: Time.now.to_f})
        body = JSON.parse(response.body)
        expect(body["headers"]).to include("X-Custom" => "value")
      end
    end

    describe "#post" do
      it "sends body" do
        response = connection.post("/users", body: {name: "Test"})
        expect(JSON.parse(response.body)["name"]).to eq("Test")
      end
    end

    describe "#head" do
      it "returns 200" do
        expect(connection.head("/health").status).to eq(200)
      end
    end
  end

  describe "#base_uri" do
    it "combines service_uri and base_path" do
      config.base_path = "/api/v1"
      expect(connection.base_uri.to_s).to include("/api/v1")
    end
  end

  describe "request with block" do
    it "yields RequestBuilder for customization" do
      response = connection.get("/echo") do |req|
        req.headers["X-Block"] = "yes"
      end
      body = JSON.parse(response.body)
      expect(body["headers"]).to include("X-Block" => "yes")
    end
  end

  describe "logging" do
    let(:log_output) { StringIO.new }
    let(:logger) { Logger.new(log_output) }
    let(:config) do
      build(:api_client_configuration, service_uri: base_url).tap do |c|
        c.log_requests = true
        c.log_bodies = true
        c.logger = logger
      end
    end

    it "logs requests when log_requests is true" do
      connection.get("/health")
      expect(log_output.string).not_to be_empty
    end
  end

  describe "error handling" do
    let(:stubbed_url) { "http://invalid.test" }

    before do
      stub_request(:get, "#{stubbed_url}/health")
        .to_raise(Faraday::ConnectionFailed.new("Connection refused"))
    end

    context "with on_error: :raise (default)" do
      let(:config) { build(:api_client_configuration, service_uri: stubbed_url) }

      it "raises on connection error" do
        expect { connection.get("/health") }.to raise_error(Faraday::ConnectionFailed)
      end
    end

    context "with on_error: :return" do
      let(:config) { build(:api_client_configuration, service_uri: stubbed_url, on_error: :return) }

      it "returns a Faraday::Response" do
        expect(connection.get("/health")).to be_a(Faraday::Response)
      end

      it "returns status 0" do
        expect(connection.get("/health").status).to eq(0)
      end

      it "returns error message as body" do
        expect(connection.get("/health").body).to eq("Connection refused")
      end
    end

    context "with on_error: :log_and_return" do
      let(:log_output) { StringIO.new }
      let(:logger) { Logger.new(log_output) }
      let(:config) do
        build(:api_client_configuration, service_uri: stubbed_url).tap do |c|
          c.on_error = :log_and_return
          c.logger = logger
        end
      end

      it "returns a Faraday::Response" do
        expect(connection.get("/health")).to be_a(Faraday::Response)
      end

      it "returns status 0" do
        expect(connection.get("/health").status).to eq(0)
      end

      it "logs the error" do
        connection.get("/health")
        expect(log_output.string).to include("ApiClient error")
      end
    end
  end

  describe ApiClient::RequestBuilder do
    subject(:builder) { described_class.new({page: 1}, {"Accept" => "text/html"}, "body") }

    describe "#url" do
      it "stores the path" do
        builder.url("/users")
        expect(builder.instance_variable_get(:@path)).to eq("/users")
      end
    end

    describe "#initialize" do
      it "dups params to avoid mutation" do
        original = {page: 1}
        b = described_class.new(original, {})
        b.params[:extra] = true
        expect(original).not_to have_key(:extra)
      end
    end
  end
end
