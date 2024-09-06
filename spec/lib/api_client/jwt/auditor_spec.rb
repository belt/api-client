require "spec_helper"

# Load JWT module
require "api_client/jwt"

RSpec.describe ApiClient::Jwt::Auditor do
  describe ".available?" do
    it "returns boolean" do
      expect(described_class.available?).to be(true).or be(false)
    end

    context "when jwt gem is installed" do
      it "returns true" do
        # jwt gem is in Gemfile for tests
        expect(described_class.available?).to be true
      end
    end
  end

  describe ".reset!" do
    after do
      # Fully clean up since reset! uses nil assignment (defined? still returns true)
      if described_class.instance_variable_defined?(:@available)
        described_class.remove_instance_variable(:@available)
      end
      if described_class.instance_variable_defined?(:@jwt_loaded)
        described_class.remove_instance_variable(:@jwt_loaded)
      end
    end

    it "clears memoized available and jwt_loaded state" do
      described_class.available?
      described_class.reset!
      expect(described_class.instance_variable_get(:@available)).to be_nil
      expect(described_class.instance_variable_get(:@jwt_loaded)).to be_nil
    end
  end

  describe ".require_jwt!" do
    after do
      if described_class.instance_variable_defined?(:@available)
        described_class.remove_instance_variable(:@available)
      end
      if described_class.instance_variable_defined?(:@jwt_loaded)
        described_class.remove_instance_variable(:@jwt_loaded)
      end
    end

    context "when jwt gem available" do
      before do
        if described_class.instance_variable_defined?(:@available)
          described_class.remove_instance_variable(:@available)
        end
        if described_class.instance_variable_defined?(:@jwt_loaded)
          described_class.remove_instance_variable(:@jwt_loaded)
        end
      end

      it "returns true" do
        expect(described_class.require_jwt!).to be true
      end

      it "loads JWT module" do
        described_class.require_jwt!
        expect(defined?(::JWT)).to eq("constant")
      end
    end

    context "when jwt gem unavailable" do
      before do
        if described_class.instance_variable_defined?(:@jwt_loaded)
          described_class.remove_instance_variable(:@jwt_loaded)
        end
        described_class.instance_variable_set(:@available, false)
      end

      it "raises JwtUnavailableError" do
        expect { described_class.require_jwt! }
          .to raise_error(ApiClient::Jwt::JwtUnavailableError)
      end
    end
  end

  describe ".validate_algorithm!" do
    context "with allowed asymmetric algorithms" do
      %w[RS256 RS384 RS512 ES256 ES384 ES512 PS256 PS384 PS512].each do |alg|
        it "accepts #{alg}" do
          expect(described_class.validate_algorithm!(alg)).to be true
        end

        it "accepts #{alg.downcase} (case insensitive)" do
          expect(described_class.validate_algorithm!(alg.downcase)).to be true
        end
      end
    end

    context "with 'none' algorithm" do
      it "raises InvalidAlgorithmError" do
        expect { described_class.validate_algorithm!("none") }
          .to raise_error(ApiClient::Jwt::InvalidAlgorithmError, /forbidden/)
      end

      it "raises for 'NONE' (case insensitive)" do
        expect { described_class.validate_algorithm!("NONE") }
          .to raise_error(ApiClient::Jwt::InvalidAlgorithmError)
      end
    end

    context "with HMAC algorithms" do
      %w[HS256 HS384 HS512].each do |alg|
        it "rejects #{alg} by default" do
          expect { described_class.validate_algorithm!(alg) }
            .to raise_error(ApiClient::Jwt::InvalidAlgorithmError, /HMAC.*discouraged/)
        end

        it "accepts #{alg} with allow_hmac: true" do
          expect(described_class.validate_algorithm!(alg, allow_hmac: true)).to be true
        end
      end
    end

    context "with unknown algorithm" do
      it "raises InvalidAlgorithmError" do
        expect { described_class.validate_algorithm!("UNKNOWN") }
          .to raise_error(ApiClient::Jwt::InvalidAlgorithmError, /not in allowed list/)
      end
    end
  end

  describe ".algorithm_allowed?" do
    it "returns true for allowed algorithms" do
      expect(described_class.algorithm_allowed?("RS256")).to be true
    end

    it "returns false for forbidden algorithms" do
      expect(described_class.algorithm_allowed?("none")).to be false
    end

    it "returns false for HMAC without allow_hmac" do
      expect(described_class.algorithm_allowed?("HS256")).to be false
    end

    it "returns true for HMAC with allow_hmac" do
      expect(described_class.algorithm_allowed?("HS256", allow_hmac: true)).to be true
    end
  end

  describe ".validate_jwk!", if: ApiClient::Jwt::Auditor.available? do
    context "with RSA JWK" do
      let(:rsa_jwk) do
        {
          kty: "RSA",
          n: "0vx7agoebGcQSuuPiLJXZptN9nndrQmbXEps2aiAFbWhM78LhWx4",
          e: "AQAB"
        }
      end

      it "accepts valid RSA JWK" do
        expect(described_class.validate_jwk!(rsa_jwk, "RS256")).to be true
      end

      it "rejects JWK missing 'n'" do
        expect { described_class.validate_jwk!({kty: "RSA", e: "AQAB"}, "RS256") }
          .to raise_error(ApiClient::Jwt::InvalidJwkError, /missing.*n/)
      end

      it "rejects JWK with wrong kty" do
        expect { described_class.validate_jwk!({kty: "EC", n: "x", e: "y"}, "RS256") }
          .to raise_error(ApiClient::Jwt::InvalidJwkError, /kty must be 'RSA'/)
      end
    end

    context "with EC JWK" do
      let(:ec_jwk) do
        {
          kty: "EC",
          crv: "P-256",
          x: "WKn-ZIGevcwGIyyrzFoZNBdaq9_TsqzGl96oc0CWuis",
          y: "y77t-RvAHRKTsSGdIYUfweuOvwrvDD-Q3Hv5J0fSKbE"
        }
      end

      it "accepts valid EC JWK" do
        expect(described_class.validate_jwk!(ec_jwk, "ES256")).to be true
      end

      it "rejects JWK missing 'crv'" do
        expect { described_class.validate_jwk!({kty: "EC", x: "x", y: "y"}, "ES256") }
          .to raise_error(ApiClient::Jwt::InvalidJwkError, /missing.*crv/)
      end
    end

    context "with symmetric JWK" do
      let(:oct_jwk) do
        {kty: "oct", k: "c2VjcmV0"}
      end

      it "accepts valid symmetric JWK" do
        expect(described_class.validate_jwk!(oct_jwk, "HS256")).to be true
      end

      it "rejects JWK missing 'k'" do
        expect { described_class.validate_jwk!({kty: "oct"}, "HS256") }
          .to raise_error(ApiClient::Jwt::InvalidJwkError, /missing.*k/)
      end
    end

    context "with unknown algorithm type" do
      it "raises InvalidJwkError" do
        expect { described_class.validate_jwk!({"kty" => "RSA"}, "UNKNOWN") }
          .to raise_error(ApiClient::Jwt::InvalidJwkError, /Unknown algorithm type/)
      end
    end

    context "with string-keyed JWK hash" do
      it "accepts valid string-keyed RSA JWK" do
        jwk = {"kty" => "RSA", "n" => "modulus", "e" => "AQAB"}
        expect(described_class.validate_jwk!(jwk, "RS256")).to be true
      end
    end

    context "with JWK object responding to export" do
      it "normalizes via export" do
        jwk_obj = instance_double("JWT::JWK::RSA")
        allow(jwk_obj).to receive(:is_a?).and_return(false)
        allow(jwk_obj).to receive(:respond_to?).with(:export).and_return(true)
        allow(jwk_obj).to receive(:export)
          .and_return({"kty" => "EC", "crv" => "P-256", "x" => "x", "y" => "y"})
        expect(described_class.validate_jwk!(jwk_obj, "ES256")).to be true
      end
    end
  end

  describe ".validate_secret_strength!" do
    it "accepts secrets >= 32 bytes" do
      secret = "a" * 32
      expect(described_class.validate_secret_strength!(secret)).to be true
    end

    it "rejects secrets < 32 bytes" do
      expect { described_class.validate_secret_strength!("short") }
        .to raise_error(ApiClient::Jwt::WeakSecretError, /at least 32 bytes/)
    end

    it "rejects nil secrets" do
      expect { described_class.validate_secret_strength!(nil) }
        .to raise_error(ApiClient::Jwt::WeakSecretError)
    end
  end

  describe ".thumbprint", if: ApiClient::Jwt::Auditor.available? do
    let(:rsa_key) { OpenSSL::PKey::RSA.generate(2048) }

    it "returns base64url-encoded string" do
      jwk = JWT::JWK.new(rsa_key)
      thumbprint = described_class.thumbprint(jwk)

      expect(thumbprint).to be_a(String)
      expect(thumbprint).to match(/\A[A-Za-z0-9_-]+\z/)
    end

    it "returns consistent thumbprint for same key" do
      jwk = JWT::JWK.new(rsa_key)
      t1 = described_class.thumbprint(jwk)
      t2 = described_class.thumbprint(jwk)

      expect(t1).to eq(t2)
    end
  end

  describe ".allowed_algorithms" do
    it "returns array of algorithm names" do
      expect(described_class.allowed_algorithms).to be_an(Array)
      expect(described_class.allowed_algorithms).to include("RS256", "ES256")
    end

    it "excludes HMAC by default" do
      expect(described_class.allowed_algorithms).not_to include("HS256")
    end

    it "includes HMAC with include_hmac: true" do
      expect(described_class.allowed_algorithms(include_hmac: true)).to include("HS256")
    end
  end

  describe "::ALLOWED_ALGORITHMS" do
    it "contains only asymmetric algorithms" do
      expect(described_class::ALLOWED_ALGORITHMS).to all(match(/^(RS|ES|PS)/))
    end
  end

  describe "::FORBIDDEN_ALGORITHMS" do
    it "contains 'none'" do
      expect(described_class::FORBIDDEN_ALGORITHMS).to include("none")
    end

    it "contains HMAC algorithms" do
      expect(described_class::FORBIDDEN_ALGORITHMS).to include("HS256", "HS384", "HS512")
    end
  end
end
