require "spec_helper"

# Load JWT module
require "api_client/jwt"
require "api_client/jwt/token"

# Skip if jwt gem not available
return unless ApiClient::Jwt::Auditor.available?

RSpec.describe ApiClient::Jwt::Token do
  let(:rsa_key) { OpenSSL::PKey::RSA.generate(2048) }
  let(:algorithm) { "RS256" }

  describe "#initialize" do
    it "sets algorithm" do
      token = described_class.new(algorithm: algorithm, key: rsa_key)
      expect(token.algorithm).to eq("RS256")
    end

    it "normalizes algorithm to uppercase" do
      token = described_class.new(algorithm: "rs256", key: rsa_key)
      expect(token.algorithm).to eq("RS256")
    end

    it "sets key" do
      token = described_class.new(algorithm: algorithm, key: rsa_key)
      expect(token.key).to eq(rsa_key)
    end

    it "sets issuer" do
      token = described_class.new(algorithm: algorithm, key: rsa_key, issuer: "test-issuer")
      expect(token.issuer).to eq("test-issuer")
    end

    it "sets audience" do
      token = described_class.new(algorithm: algorithm, key: rsa_key, audience: "test-audience")
      expect(token.audience).to eq("test-audience")
    end

    context "with forbidden algorithm" do
      it "raises InvalidAlgorithmError for 'none'" do
        expect { described_class.new(algorithm: "none", key: nil) }
          .to raise_error(ApiClient::Jwt::InvalidAlgorithmError)
      end

      it "raises InvalidAlgorithmError for HMAC without allow_hmac" do
        expect { described_class.new(algorithm: "HS256", key: "secret" * 10) }
          .to raise_error(ApiClient::Jwt::InvalidAlgorithmError)
      end
    end

    context "with HMAC and allow_hmac: true" do
      let(:strong_secret) { "a" * 32 }

      it "accepts HMAC algorithm" do
        token = described_class.new(algorithm: "HS256", key: strong_secret, allow_hmac: true)
        expect(token.algorithm).to eq("HS256")
      end

      it "validates secret strength" do
        expect { described_class.new(algorithm: "HS256", key: "weak", allow_hmac: true) }
          .to raise_error(ApiClient::Jwt::WeakSecretError)
      end
    end
  end

  describe "#encode" do
    subject(:token) { described_class.new(algorithm: algorithm, key: rsa_key) }

    it "returns JWT string" do
      jwt = token.encode({sub: "user123"})
      expect(jwt).to be_a(String)
      expect(jwt.split(".").size).to eq(3)
    end

    it "includes payload claims" do
      jwt = token.encode({sub: "user123", custom: "value"})
      payload, = JWT.decode(jwt, rsa_key.public_key, true, algorithm: "RS256")

      expect(payload["sub"]).to eq("user123")
      expect(payload["custom"]).to eq("value")
    end

    it "adds exp claim" do
      jwt = token.encode({sub: "user123"}, expires_in: 3600)
      payload, = JWT.decode(jwt, rsa_key.public_key, true, algorithm: "RS256")

      expect(payload["exp"]).to be_within(5).of(Time.now.to_i + 3600)
    end

    it "adds iat claim" do
      jwt = token.encode({sub: "user123"})
      payload, = JWT.decode(jwt, rsa_key.public_key, true, algorithm: "RS256")

      expect(payload["iat"]).to be_within(5).of(Time.now.to_i)
    end

    it "adds jti claim" do
      jwt = token.encode({sub: "user123"})
      payload, = JWT.decode(jwt, rsa_key.public_key, true, algorithm: "RS256")

      expect(payload["jti"]).to match(/\A[0-9a-f-]{36}\z/)
    end

    it "allows custom jti" do
      jwt = token.encode({sub: "user123"}, jwt_id: "custom-id")
      payload, = JWT.decode(jwt, rsa_key.public_key, true, algorithm: "RS256")

      expect(payload["jti"]).to eq("custom-id")
    end

    context "with issuer configured" do
      subject(:token) do
        described_class.new(algorithm: algorithm, key: rsa_key, issuer: "test-issuer")
      end

      it "adds iss claim" do
        jwt = token.encode({sub: "user123"})
        payload, = JWT.decode(jwt, rsa_key.public_key, true, algorithm: "RS256")

        expect(payload["iss"]).to eq("test-issuer")
      end
    end

    context "with audience configured" do
      subject(:token) do
        described_class.new(algorithm: algorithm, key: rsa_key, audience: "test-audience")
      end

      it "adds aud claim" do
        jwt = token.encode({sub: "user123"})
        payload, = JWT.decode(jwt, rsa_key.public_key, true, algorithm: "RS256")

        expect(payload["aud"]).to eq("test-audience")
      end
    end

    it "adds nbf claim when specified" do
      nbf_time = Time.now.to_i + 60
      jwt = token.encode({sub: "user123"}, not_before: nbf_time)
      # Decode without verification to check nbf was set (token is not yet valid)
      payload, = JWT.decode(jwt, nil, false)

      expect(payload["nbf"]).to eq(nbf_time)
    end

    it "sets typ header to JWT" do
      jwt = token.encode({sub: "user123"})
      _, header = JWT.decode(jwt, rsa_key.public_key, true, algorithm: "RS256")

      expect(header["typ"]).to eq("JWT")
    end
  end

  describe "#decode" do
    subject(:token) { described_class.new(algorithm: algorithm, key: rsa_key.public_key) }

    let(:valid_jwt) do
      JWT.encode(
        {sub: "user123", exp: Time.now.to_i + 3600, iat: Time.now.to_i},
        rsa_key,
        "RS256"
      )
    end

    it "returns [payload, header]" do
      result = token.decode(valid_jwt)
      expect(result).to be_an(Array)
      expect(result.size).to eq(2)
    end

    it "decodes payload" do
      payload, = token.decode(valid_jwt)
      expect(payload["sub"]).to eq("user123")
    end

    it "decodes header" do
      _, header = token.decode(valid_jwt)
      expect(header["alg"]).to eq("RS256")
    end

    context "with expired token" do
      let(:expired_jwt) do
        JWT.encode(
          {sub: "user123", exp: Time.now.to_i - 3600, iat: Time.now.to_i - 7200},
          rsa_key,
          "RS256"
        )
      end

      it "raises TokenVerificationError" do
        expect { token.decode(expired_jwt) }
          .to raise_error(ApiClient::Jwt::TokenVerificationError)
      end

      it "accepts with leeway" do
        expect { token.decode(expired_jwt, leeway: 7200) }
          .not_to raise_error
      end

      it "accepts with verify_expiration: false" do
        expect { token.decode(expired_jwt, verify_expiration: false) }
          .not_to raise_error
      end
    end

    context "with issuer validation" do
      subject(:token) do
        described_class.new(
          algorithm: algorithm,
          key: rsa_key.public_key,
          issuer: "expected-issuer"
        )
      end

      let(:wrong_issuer_jwt) do
        JWT.encode(
          {sub: "user123", exp: Time.now.to_i + 3600, iat: Time.now.to_i, iss: "wrong-issuer"},
          rsa_key,
          "RS256"
        )
      end

      it "raises TokenVerificationError for wrong issuer" do
        expect { token.decode(wrong_issuer_jwt) }
          .to raise_error(ApiClient::Jwt::TokenVerificationError)
      end
    end

    context "with audience validation" do
      subject(:token) do
        described_class.new(
          algorithm: algorithm,
          key: rsa_key.public_key,
          audience: "expected-audience"
        )
      end

      let(:wrong_audience_jwt) do
        JWT.encode(
          {sub: "user123", exp: Time.now.to_i + 3600, iat: Time.now.to_i, aud: "wrong-audience"},
          rsa_key,
          "RS256"
        )
      end

      it "raises TokenVerificationError for wrong audience" do
        expect { token.decode(wrong_audience_jwt) }
          .to raise_error(ApiClient::Jwt::TokenVerificationError)
      end
    end

    context "with invalid signature" do
      let(:other_key) { OpenSSL::PKey::RSA.generate(2048) }
      let(:bad_signature_jwt) do
        JWT.encode({sub: "user123", exp: Time.now.to_i + 3600}, other_key, "RS256")
      end

      it "raises TokenVerificationError" do
        expect { token.decode(bad_signature_jwt) }
          .to raise_error(ApiClient::Jwt::TokenVerificationError)
      end
    end
  end

  describe "#decode_unverified" do
    subject(:token) { described_class.new(algorithm: algorithm, key: rsa_key) }

    let(:jwt) do
      JWT.encode({sub: "user123", exp: Time.now.to_i - 3600}, rsa_key, "RS256")
    end

    it "decodes without verification" do
      payload, = token.decode_unverified(jwt)
      expect(payload["sub"]).to eq("user123")
    end

    it "does not raise for expired tokens" do
      expect { token.decode_unverified(jwt) }.not_to raise_error
    end
  end

  describe "#peek_header" do
    subject(:token) { described_class.new(algorithm: algorithm, key: rsa_key) }

    let(:jwt) { JWT.encode({sub: "user123"}, rsa_key, "RS256", {kid: "key-123"}) }

    it "returns header hash" do
      header = token.peek_header(jwt)
      expect(header).to be_a(Hash)
      expect(header["alg"]).to eq("RS256")
    end

    it "includes kid if present" do
      header = token.peek_header(jwt)
      expect(header["kid"]).to eq("key-123")
    end
  end

  describe "#extract_kid" do
    subject(:token) { described_class.new(algorithm: algorithm, key: rsa_key) }

    it "returns kid from header" do
      jwt = JWT.encode({sub: "user123"}, rsa_key, "RS256", {kid: "key-123"})
      expect(token.extract_kid(jwt)).to eq("key-123")
    end

    it "returns nil if no kid" do
      jwt = JWT.encode({sub: "user123"}, rsa_key, "RS256")
      expect(token.extract_kid(jwt)).to be_nil
    end
  end

  describe "round-trip encode/decode" do
    let(:encoder) {
      described_class.new(
        algorithm: algorithm, key: rsa_key, issuer: "test", audience: "api"
      )
    }
    let(:decoder) {
      described_class.new(
        algorithm: algorithm, key: rsa_key.public_key, issuer: "test", audience: "api"
      )
    }

    it "successfully round-trips" do
      original_payload = {sub: "user123", role: "admin"}
      jwt = encoder.encode(original_payload)
      decoded_payload, = decoder.decode(jwt)

      expect(decoded_payload["sub"]).to eq("user123")
      expect(decoded_payload["role"]).to eq("admin")
    end
  end

  describe "#encode with Time objects" do
    subject(:token) { described_class.new(algorithm: algorithm, key: rsa_key) }

    it "accepts Time for issued_at" do
      time = Time.now - 60
      jwt = token.encode({sub: "user"}, issued_at: time)
      payload, = JWT.decode(jwt, rsa_key.public_key, true, algorithm: "RS256")
      expect(payload["iat"]).to eq(time.to_i)
    end

    it "accepts non-integer coercible for issued_at" do
      float_iat = Time.now.to_f
      jwt = token.encode({sub: "user"}, issued_at: float_iat)
      payload, = JWT.decode(jwt, rsa_key.public_key, true, algorithm: "RS256")
      expect(payload["iat"]).to eq(float_iat.to_i)
    end
  end

  describe "key handling" do
    context "with JWK-like key responding to verify_key" do
      it "uses verify_key for decoding" do
        jwk = JWT::JWK.new(rsa_key)
        encoder = described_class.new(algorithm: "RS256", key: jwk)
        jwt = encoder.encode({sub: "user123"})

        decoder = described_class.new(algorithm: "RS256", key: jwk)
        payload, = decoder.decode(jwt)
        expect(payload["sub"]).to eq("user123")
      end
    end

    context "with key containing kid" do
      it "includes kid in header" do
        jwk = JWT::JWK.new(rsa_key)
        token = described_class.new(algorithm: "RS256", key: jwk)
        jwt = token.encode({sub: "user123"})
        header = token.peek_header(jwt)
        expect(header["kid"]).not_to be_nil
      end
    end
  end
end
