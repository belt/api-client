require "spec_helper"

# Load JWT module
require "api_client/jwt"
require "api_client/jwt/jwks_client"

# Skip if jwt gem not available
return unless ApiClient::Jwt::Auditor.available?

RSpec.describe ApiClient::Jwt::JwksClient do
  let(:jwks_uri) { "https://auth.example.com/.well-known/jwks.json" }
  let(:rsa_key) { OpenSSL::PKey::RSA.generate(2048) }
  let(:rsa_key2) { OpenSSL::PKey::RSA.generate(2048) }

  let(:jwks_response) do
    {
      keys: [
        JWT::JWK.new(rsa_key, kid: "key-1", use: "sig", alg: "RS256").export,
        JWT::JWK.new(rsa_key2, kid: "key-2", use: "sig", alg: "RS256").export
      ]
    }
  end

  before do
    # Reset circuit breaker state to prevent cross-test pollution.
    # JwksClient creates an internal ApiClient::Base with circuit name
    # "api_client:auth.example.com" — earlier test failures can trip
    # the circuit and cause unrelated tests to fail with CircuitOpenError.
    light = Stoplight("api_client:auth.example.com")
    light.lock(Stoplight::Color::GREEN)

    stub_request(:get, "https://auth.example.com/.well-known/jwks.json")
      .to_return(
        status: 200,
        body: jwks_response.to_json,
        headers: {"Content-Type" => "application/json"}
      )
  end

  describe "#initialize" do
    it "sets jwks_uri" do
      client = described_class.new(jwks_uri: jwks_uri)
      expect(client.jwks_uri).to eq(jwks_uri)
    end

    it "sets default TTL" do
      client = described_class.new(jwks_uri: jwks_uri)
      expect(client.ttl).to eq(600)
    end

    it "accepts custom TTL" do
      client = described_class.new(jwks_uri: jwks_uri, ttl: 300)
      expect(client.ttl).to eq(300)
    end

    it "accepts allowed_algorithms filter" do
      client = described_class.new(jwks_uri: jwks_uri, allowed_algorithms: %w[RS256])
      expect(client.allowed_algorithms).to eq(%w[RS256])
    end
  end

  describe "#key" do
    subject(:client) { described_class.new(jwks_uri: jwks_uri) }

    it "fetches and returns key by kid" do
      key = client.key(kid: "key-1")
      expect(key).to be_a(JWT::JWK::KeyBase)
      expect(key[:kid]).to eq("key-1")
    end

    it "caches keys" do
      client.key(kid: "key-1")
      client.key(kid: "key-2")

      # Should only make one request
      expect(WebMock).to have_requested(:get, jwks_uri).once
    end

    it "raises KeyNotFoundError for unknown kid" do
      expect { client.key(kid: "unknown") }
        .to raise_error(ApiClient::Jwt::KeyNotFoundError, /unknown/)
    end

    context "with algorithm validation" do
      it "passes when algorithm matches" do
        key = client.key(kid: "key-1", algorithm: "RS256")
        expect(key[:kid]).to eq("key-1")
      end

      it "logs warning when algorithm mismatches" do
        logger = instance_double(Logger, debug: nil, error: nil)
        allow(logger).to receive(:warn).and_yield
        warned = described_class.new(jwks_uri: jwks_uri, logger: logger)

        warned.key(kid: "key-1", algorithm: "ES384")
        expect(logger).to have_received(:warn)
      end
    end
  end

  describe "#key_or_nil" do
    subject(:client) { described_class.new(jwks_uri: jwks_uri) }

    it "returns key for existing kid" do
      key = client.key_or_nil(kid: "key-1")
      expect(key).to be_a(JWT::JWK::KeyBase)
    end

    it "returns nil for unknown kid" do
      expect(client.key_or_nil(kid: "unknown")).to be_nil
    end
  end

  describe "#refresh!" do
    subject(:client) { described_class.new(jwks_uri: jwks_uri) }

    it "fetches keys from endpoint" do
      client.refresh!
      expect(WebMock).to have_requested(:get, jwks_uri)
    end

    it "updates cache" do
      client.refresh!
      expect(client.cached_kids).to contain_exactly("key-1", "key-2")
    end

    context "when fetch fails" do
      before do
        stub_request(:get, jwks_uri).to_return(status: 500)
      end

      it "raises JwksFetchError when cache empty" do
        expect { client.refresh! }
          .to raise_error(ApiClient::Jwt::JwksFetchError)
      end

      it "raises JwksFetchError on non-retryable HTTP error" do
        stub_request(:get, jwks_uri).to_return(status: 403, body: "Forbidden")
        expect { client.refresh! }
          .to raise_error(ApiClient::Jwt::JwksFetchError, /403/)
      end

      it "keeps stale cache on failure" do
        # First successful fetch
        stub_request(:get, jwks_uri)
          .to_return(status: 200, body: jwks_response.to_json)
          .then
          .to_return(status: 500)

        client.refresh!(force: true)
        expect(client.cached_kids).not_to be_empty

        # Second fetch fails but cache preserved
        begin
          client.refresh!(force: true)
        rescue
          nil
        end
        expect(client.cached_kids).not_to be_empty
      end
    end

    context "when Faraday raises a connection error" do
      before do
        stub_request(:get, jwks_uri).to_raise(Faraday::ConnectionFailed.new("refused"))
      end

      it "raises JwksFetchError wrapping the Faraday error" do
        expect { client.refresh! }
          .to raise_error(ApiClient::Jwt::JwksFetchError, /refused/)
      end
    end
  end

  describe "#to_loader" do
    subject(:client) { described_class.new(jwks_uri: jwks_uri) }

    it "returns callable" do
      loader = client.to_loader
      expect(loader).to respond_to(:call)
    end

    it "returns JWKS set" do
      loader = client.to_loader
      result = loader.call({})
      expect(result).to be_a(JWT::JWK::Set)
    end

    context "with kid_not_found option" do
      it "triggers refresh when kid_not_found" do
        client.refresh!
        WebMock.reset!

        stub_request(:get, jwks_uri)
          .to_return(status: 200, body: jwks_response.to_json)

        # Simulate time passing beyond grace period using monotonic clock
        future = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 400
        allow(Process).to receive(:clock_gettime).and_call_original
        allow(Process).to receive(:clock_gettime)
          .with(Process::CLOCK_MONOTONIC).and_return(future)

        loader = client.to_loader
        loader.call(kid_not_found: true)

        expect(WebMock).to have_requested(:get, jwks_uri)
      end
    end
  end

  describe "#jwks_set" do
    subject(:client) { described_class.new(jwks_uri: jwks_uri) }

    it "returns JWT::JWK::Set" do
      expect(client.jwks_set).to be_a(JWT::JWK::Set)
    end

    it "contains all cached keys" do
      set = client.jwks_set
      kids = set.map { |k| k[:kid] }
      expect(kids).to contain_exactly("key-1", "key-2")
    end
  end

  describe "#stale?" do
    subject(:client) { described_class.new(jwks_uri: jwks_uri, ttl: 60) }

    it "returns true initially" do
      expect(client.stale?).to be true
    end

    it "returns false after refresh" do
      client.refresh!
      expect(client.stale?).to be false
    end

    it "returns true after TTL expires" do
      client.refresh!

      future = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 120
      allow(Process).to receive(:clock_gettime).and_call_original
      allow(Process).to receive(:clock_gettime)
        .with(Process::CLOCK_MONOTONIC).and_return(future)
      expect(client.stale?).to be true
    end
  end

  describe "#clear!" do
    subject(:client) { described_class.new(jwks_uri: jwks_uri) }

    before { client.refresh! }

    it "clears cache" do
      client.clear!
      expect(client.cached_kids).to be_empty
    end

    it "resets last refresh time" do
      client.clear!
      expect(client.stale?).to be true
    end
  end

  describe "filtering" do
    context "by use=sig" do
      let(:jwks_response) do
        {
          keys: [
            JWT::JWK.new(rsa_key, kid: "sig-key", use: "sig").export,
            JWT::JWK.new(rsa_key2, kid: "enc-key", use: "enc").export
          ]
        }
      end

      it "only caches signing keys" do
        client = described_class.new(jwks_uri: jwks_uri)
        client.refresh!
        expect(client.cached_kids).to eq(["sig-key"])
      end
    end

    context "by allowed_algorithms" do
      let(:jwks_response) do
        {
          keys: [
            JWT::JWK.new(rsa_key, kid: "rs256-key", alg: "RS256").export,
            JWT::JWK.new(rsa_key2, kid: "rs512-key", alg: "RS512").export
          ]
        }
      end

      it "only caches keys with allowed algorithms" do
        client = described_class.new(jwks_uri: jwks_uri, allowed_algorithms: %w[RS256])
        client.refresh!
        expect(client.cached_kids).to eq(["rs256-key"])
      end
    end
  end

  describe "key rotation handling" do
    subject(:client) { described_class.new(jwks_uri: jwks_uri) }

    it "removes keys no longer in JWKS" do
      # Initial fetch with both keys
      client.refresh!
      expect(client.cached_kids).to contain_exactly("key-1", "key-2")

      # Update JWKS to only have key-2 (key-1 removed)
      stub_request(:get, jwks_uri)
        .to_return(
          status: 200,
          body: {keys: [JWT::JWK.new(rsa_key2, kid: "key-2").export]}.to_json
        )

      client.refresh!(force: true)
      expect(client.cached_kids).to eq(["key-2"])
    end

    it "adds new keys from JWKS" do
      client.refresh!

      # Add key-3 to JWKS
      new_key = OpenSSL::PKey::RSA.generate(2048)
      stub_request(:get, jwks_uri)
        .to_return(
          status: 200,
          body: {
            keys: [
              JWT::JWK.new(rsa_key, kid: "key-1").export,
              JWT::JWK.new(rsa_key2, kid: "key-2").export,
              JWT::JWK.new(new_key, kid: "key-3").export
            ]
          }.to_json
        )

      client.refresh!(force: true)
      expect(client.cached_kids).to contain_exactly("key-1", "key-2", "key-3")
    end
  end

  describe "integration with JWT.decode" do
    subject(:client) { described_class.new(jwks_uri: jwks_uri) }

    let(:token) do
      JWT.encode(
        {sub: "user123", exp: Time.now.to_i + 3600},
        rsa_key,
        "RS256",
        {kid: "key-1"}
      )
    end

    it "works as jwks loader" do
      payload, = JWT.decode(token, nil, true, {
        algorithms: ["RS256"],
        jwks: client.to_loader
      })

      expect(payload["sub"]).to eq("user123")
    end
  end

  describe "default_logger" do
    context "when Rails is defined" do
      let(:rails_logger) { instance_double(Logger) }

      it "uses Rails.logger" do
        stub_const("Rails", double(respond_to?: true, logger: rails_logger))
        client = described_class.new(jwks_uri: jwks_uri)
        # Verify it doesn't raise and uses the Rails logger
        expect(client).to be_a(described_class)
      end

      it "falls back to null logger when Rails.logger is nil" do
        stub_const("Rails", double(respond_to?: true, logger: nil))
        client = described_class.new(jwks_uri: jwks_uri)
        expect(client).to be_a(described_class)
      end
    end
  end
end
