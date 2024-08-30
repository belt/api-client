require "spec_helper"

# Load JWT module
require "api_client/jwt"

RSpec.describe "ApiClient::Jwt errors" do
  describe ApiClient::Jwt::Error do
    it "inherits from ApiClient::Error" do
      expect(described_class.superclass).to eq(ApiClient::Error)
    end
  end

  describe ApiClient::Jwt::JwtUnavailableError do
    it "has default message" do
      error = described_class.new
      expect(error.message).to include("jwt gem not available")
    end

    it "accepts custom message" do
      error = described_class.new("custom message")
      expect(error.message).to eq("custom message")
    end
  end

  describe ApiClient::Jwt::InvalidAlgorithmError do
    it "stores algorithm" do
      error = described_class.new("HS256", "not allowed")
      expect(error.algorithm).to eq("HS256")
    end

    it "has default message" do
      error = described_class.new("HS256")
      expect(error.message).to include("HS256")
    end
  end

  describe ApiClient::Jwt::InvalidJwkError do
    it "inherits from Jwt::Error" do
      expect(described_class.superclass).to eq(ApiClient::Jwt::Error)
    end
  end

  describe ApiClient::Jwt::WeakSecretError do
    it "inherits from Jwt::Error" do
      expect(described_class.superclass).to eq(ApiClient::Jwt::Error)
    end
  end

  describe ApiClient::Jwt::KeyNotFoundError do
    it "stores kid" do
      error = described_class.new(kid: "key-123")
      expect(error.kid).to eq("key-123")
    end

    it "stores jwks_uri" do
      error = described_class.new(kid: "key-123", jwks_uri: "https://example.com/jwks")
      expect(error.jwks_uri).to eq("https://example.com/jwks")
    end

    it "includes kid in message" do
      error = described_class.new(kid: "key-123")
      expect(error.message).to include("key-123")
    end

    it "includes jwks_uri in message when provided" do
      error = described_class.new(kid: "key-123", jwks_uri: "https://example.com/jwks")
      expect(error.message).to include("https://example.com/jwks")
    end
  end

  describe ApiClient::Jwt::JwksFetchError do
    it "stores uri" do
      error = described_class.new(uri: "https://example.com/jwks", status: 500)
      expect(error.uri).to eq("https://example.com/jwks")
    end

    it "stores status" do
      error = described_class.new(uri: "https://example.com/jwks", status: 500)
      expect(error.status).to eq(500)
    end

    it "includes uri and status in message" do
      error = described_class.new(uri: "https://example.com/jwks", status: 500)
      expect(error.message).to include("https://example.com/jwks")
      expect(error.message).to include("500")
    end
  end

  describe ApiClient::Jwt::TokenVerificationError do
    it "stores original error" do
      original = StandardError.new("original")
      error = described_class.new(original)
      expect(error.original_error).to eq(original)
    end

    it "uses original error message" do
      original = StandardError.new("signature invalid")
      error = described_class.new(original)
      expect(error.message).to eq("signature invalid")
    end

    it "accepts custom message" do
      error = described_class.new(nil, "custom message")
      expect(error.message).to eq("custom message")
    end

    it "has fallback message" do
      error = described_class.new(nil, nil)
      expect(error.message).to eq("Token verification failed")
    end
  end
end
