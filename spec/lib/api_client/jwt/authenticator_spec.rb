require "spec_helper"

# Load JWT module
require "api_client/jwt"
require "api_client/jwt/authenticator"

RSpec.describe ApiClient::Jwt::Authenticator do
  describe "#initialize" do
    it "accepts string token" do
      auth = described_class.new(token_provider: "my-token")
      expect(auth.token).to eq("my-token")
    end

    it "accepts proc token provider" do
      auth = described_class.new(token_provider: -> { "dynamic-token" })
      expect(auth.token).to eq("dynamic-token")
    end

    it "sets default header name" do
      auth = described_class.new(token_provider: "token")
      expect(auth.header_name).to eq("Authorization")
    end

    it "sets default scheme" do
      auth = described_class.new(token_provider: "token")
      expect(auth.scheme).to eq("Bearer")
    end

    it "accepts custom header name" do
      auth = described_class.new(token_provider: "token", header_name: "X-Auth-Token")
      expect(auth.header_name).to eq("X-Auth-Token")
    end

    it "accepts custom scheme" do
      auth = described_class.new(token_provider: "token", scheme: "Token")
      expect(auth.scheme).to eq("Token")
    end
  end

  describe "#headers" do
    it "returns hash with authorization header" do
      auth = described_class.new(token_provider: "my-token")
      expect(auth.headers).to eq({"Authorization" => "Bearer my-token"})
    end

    it "uses custom header name" do
      auth = described_class.new(token_provider: "my-token", header_name: "X-Token")
      expect(auth.headers).to have_key("X-Token")
    end

    it "uses custom scheme" do
      auth = described_class.new(token_provider: "my-token", scheme: "Token")
      expect(auth.headers["Authorization"]).to eq("Token my-token")
    end
  end

  describe "#authorization_value" do
    it "returns scheme + token" do
      auth = described_class.new(token_provider: "my-token")
      expect(auth.authorization_value).to eq("Bearer my-token")
    end
  end

  describe "#token" do
    context "with string provider" do
      it "returns the string" do
        auth = described_class.new(token_provider: "static-token")
        expect(auth.token).to eq("static-token")
      end
    end

    context "with proc provider" do
      it "calls the proc" do
        counter = 0
        auth = described_class.new(token_provider: -> {
          counter += 1
          "token-#{counter}"
        })

        expect(auth.token).to eq("token-1")
        expect(auth.token).to eq("token-2")
      end
    end

    context "with callable object" do
      let(:token_generator) do
        Class.new do
          def initialize
            @counter = 0
          end

          def call
            @counter += 1
            "generated-#{@counter}"
          end
        end.new
      end

      it "calls the object" do
        auth = described_class.new(token_provider: token_generator)
        expect(auth.token).to eq("generated-1")
        expect(auth.token).to eq("generated-2")
      end
    end
  end

  describe "Faraday middleware" do
    let(:stubs) { Faraday::Adapter::Test::Stubs.new }
    let(:connection) do
      Faraday.new do |f|
        f.use described_class.middleware(token_provider: "test-token")
        f.adapter :test, stubs
      end
    end

    before do
      stubs.get("/test") do |env|
        [200, {}, env.request_headers["Authorization"]]
      end
    end

    it "adds authorization header to requests" do
      response = connection.get("/test")
      expect(response.body).to eq("Bearer test-token")
    end

    context "with dynamic token" do
      let(:connection) do
        counter = 0
        Faraday.new do |f|
          f.use described_class.middleware(token_provider: -> {
            counter += 1
            "token-#{counter}"
          })
          f.adapter :test, stubs
        end
      end

      it "generates fresh token per request" do
        response1 = connection.get("/test")
        response2 = connection.get("/test")

        expect(response1.body).to eq("Bearer token-1")
        expect(response2.body).to eq("Bearer token-2")
      end
    end
  end

  describe "direct middleware interface" do
    let(:app) { double("app") }
    let(:middleware_class) { described_class.middleware(token_provider: "direct-token") }
    let(:middleware) { middleware_class.new(app) }

    it "creates a Faraday::Middleware subclass" do
      expect(middleware_class.ancestors).to include(Faraday::Middleware)
    end

    it "injects authorization header and calls app" do
      env = Faraday::Env.new
      env.request_headers = {}

      expect(app).to receive(:call).with(env)
      middleware.call(env)

      expect(env.request_headers["Authorization"]).to eq("Bearer direct-token")
    end
  end

  describe "integration with ApiClient", if: ApiClient::Jwt::Auditor.available? do
    let(:rsa_key) { OpenSSL::PKey::RSA.generate(2048) }

    it "works with Token for signing" do
      require "api_client/jwt/token"

      signer = ApiClient::Jwt::Token.new(algorithm: "RS256", key: rsa_key)
      auth = described_class.new(
        token_provider: -> { signer.encode({sub: "service"}) }
      )

      headers = auth.headers
      expect(headers["Authorization"]).to start_with("Bearer eyJ")

      # Verify the token is valid
      token = headers["Authorization"].sub("Bearer ", "")
      payload, = JWT.decode(token, rsa_key.public_key, true, algorithm: "RS256")
      expect(payload["sub"]).to eq("service")
    end
  end
end
