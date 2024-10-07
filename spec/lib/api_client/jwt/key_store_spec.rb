require "spec_helper"

# Load JWT module
require "api_client/jwt"
require "api_client/jwt/key_store"

# Skip if jwt gem not available
return unless ApiClient::Jwt::Auditor.available?

RSpec.describe ApiClient::Jwt::KeyStore do
  subject(:store) { described_class.new }

  let(:rsa_key) { OpenSSL::PKey::RSA.generate(2048) }
  let(:rsa_key2) { OpenSSL::PKey::RSA.generate(2048) }

  describe "#initialize" do
    it "creates empty store" do
      expect(store).to be_empty
    end
  end

  describe "#add" do
    it "adds key to store" do
      store.add(rsa_key, kid: "key-1")
      expect(store.key?("key-1")).to be true
    end

    it "returns kid" do
      kid = store.add(rsa_key, kid: "key-1")
      expect(kid).to eq("key-1")
    end

    it "auto-generates kid from thumbprint if not provided" do
      jwk = JWT::JWK.new(rsa_key)
      kid = store.add(jwk)
      expect(kid).to be_a(String)
      expect(kid.length).to be > 10
    end

    it "uses kid from JWK if present" do
      jwk = JWT::JWK.new(rsa_key, kid: "jwk-kid")
      kid = store.add(jwk)
      expect(kid).to eq("jwk-kid")
    end

    it "accepts OpenSSL key" do
      store.add(rsa_key, kid: "key-1")
      expect(store.get("key-1")).to be_a(JWT::JWK::KeyBase)
    end

    it "accepts JWK" do
      jwk = JWT::JWK.new(rsa_key)
      store.add(jwk, kid: "key-1")
      expect(store.get("key-1")).to be_a(JWT::JWK::KeyBase)
    end

    it "accepts Hash" do
      jwk_hash = JWT::JWK.new(rsa_key).export(include_private: true)
      store.add(jwk_hash, kid: "key-1")
      expect(store.get("key-1")).to be_a(JWT::JWK::KeyBase)
    end

    context "with state: :signing" do
      it "sets as signing key" do
        store.add(rsa_key, kid: "key-1", state: :signing)
        expect(store.signing_kid).to eq("key-1")
      end
    end
  end

  describe "#get" do
    before { store.add(rsa_key, kid: "key-1") }

    it "returns JWK for existing key" do
      expect(store.get("key-1")).to be_a(JWT::JWK::KeyBase)
    end

    it "returns nil for non-existent key" do
      expect(store.get("unknown")).to be_nil
    end
  end

  describe "#get!" do
    before { store.add(rsa_key, kid: "key-1") }

    it "returns JWK for existing key" do
      expect(store.get!("key-1")).to be_a(JWT::JWK::KeyBase)
    end

    it "raises KeyNotFoundError for non-existent key" do
      expect { store.get!("unknown") }
        .to raise_error(ApiClient::Jwt::KeyNotFoundError)
    end
  end

  describe "#signing_key" do
    it "returns nil when no signing key set" do
      store.add(rsa_key, kid: "key-1")
      expect(store.signing_key).to be_nil
    end

    it "returns signing key when set" do
      store.add(rsa_key, kid: "key-1", state: :signing)
      expect(store.signing_key).to be_a(JWT::JWK::KeyBase)
    end
  end

  describe "#activate" do
    before do
      store.add(rsa_key, kid: "key-1")
      store.add(rsa_key2, kid: "key-2")
    end

    it "sets key as signing key" do
      store.activate("key-1")
      expect(store.signing_kid).to eq("key-1")
    end

    it "demotes previous signing key" do
      store.add(rsa_key, kid: "key-old", state: :signing)
      store.activate("key-1")
      expect(store.signing_kid).to eq("key-1")
    end

    it "raises KeyNotFoundError for unknown key" do
      expect { store.activate("unknown") }
        .to raise_error(ApiClient::Jwt::KeyNotFoundError)
    end
  end

  describe "#retire" do
    before { store.add(rsa_key, kid: "key-1", state: :signing) }

    it "marks key as retired" do
      store.retire("key-1")
      expect(store.kids(state: :retired)).to include("key-1")
    end

    it "clears signing key if retired" do
      store.retire("key-1")
      expect(store.signing_kid).to be_nil
    end

    it "keeps key in store" do
      store.retire("key-1")
      expect(store.key?("key-1")).to be true
    end
  end

  describe "#remove" do
    before { store.add(rsa_key, kid: "key-1") }

    it "removes key from store" do
      store.remove("key-1")
      expect(store.key?("key-1")).to be false
    end

    it "returns removed JWK" do
      result = store.remove("key-1")
      expect(result).to be_a(JWT::JWK::KeyBase)
    end

    it "returns nil for non-existent key" do
      expect(store.remove("unknown")).to be_nil
    end
  end

  describe "#kids" do
    before do
      store.add(rsa_key, kid: "key-1", state: :active)
      store.add(rsa_key2, kid: "key-2", state: :signing)
    end

    it "returns all key IDs" do
      expect(store.kids).to contain_exactly("key-1", "key-2")
    end

    it "filters by state" do
      expect(store.kids(state: :signing)).to eq(["key-2"])
    end
  end

  describe "#to_jwks" do
    before do
      store.add(rsa_key, kid: "key-1")
      store.add(rsa_key2, kid: "key-2")
    end

    it "returns JWKS hash" do
      jwks = store.to_jwks
      expect(jwks).to have_key(:keys)
      expect(jwks[:keys].size).to eq(2)
    end

    it "excludes retired keys when requested" do
      store.retire("key-1")
      jwks = store.to_jwks(include_retired: false)
      expect(jwks[:keys].size).to eq(1)
    end
  end

  describe "#import_jwks" do
    let(:jwks_hash) do
      {
        keys: [
          JWT::JWK.new(rsa_key, kid: "imported-1").export,
          JWT::JWK.new(rsa_key2, kid: "imported-2").export
        ]
      }
    end

    it "imports keys from JWKS" do
      store.import_jwks(jwks_hash)
      expect(store.kids).to contain_exactly("imported-1", "imported-2")
    end

    it "returns imported key IDs" do
      kids = store.import_jwks(jwks_hash)
      expect(kids).to contain_exactly("imported-1", "imported-2")
    end
  end

  describe "#clear!" do
    before do
      store.add(rsa_key, kid: "key-1", state: :signing)
      store.add(rsa_key2, kid: "key-2")
    end

    it "removes all keys" do
      store.clear!
      expect(store).to be_empty
    end

    it "clears signing key" do
      store.clear!
      expect(store.signing_kid).to be_nil
    end
  end

  describe "#size" do
    it "returns 0 for empty store" do
      expect(store.size).to eq(0)
    end

    it "returns key count" do
      store.add(rsa_key, kid: "key-1")
      store.add(rsa_key2, kid: "key-2")
      expect(store.size).to eq(2)
    end
  end

  describe "key rotation workflow" do
    it "supports 4-phase rotation" do
      # Phase 1: Normal operation
      store.add(rsa_key, kid: "key-2025-01", state: :signing)
      expect(store.signing_kid).to eq("key-2025-01")

      # Phase 2: Introduce new key
      store.add(rsa_key2, kid: "key-2025-04")
      expect(store.kids).to contain_exactly("key-2025-01", "key-2025-04")

      # Phase 3: Switch to new key
      store.activate("key-2025-04")
      store.retire("key-2025-01")
      expect(store.signing_kid).to eq("key-2025-04")
      expect(store.key?("key-2025-01")).to be true  # Still available for verification

      # Phase 4: Remove old key
      store.remove("key-2025-01")
      expect(store.kids).to eq(["key-2025-04"])
    end
  end
end
