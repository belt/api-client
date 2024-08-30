require "spec_helper"
require "api_client"
require "api_client/jwt"

RSpec.describe ApiClient::Jwt do
  before do
    ApiClient::Jwt::Auditor.reset!
  end

  describe ".available?" do
    it "returns true when jwt gem is available" do
      expect(described_class.available?).to be true
    end
  end

  describe ".require!" do
    it "succeeds when jwt gem is available" do
      expect(described_class.require!).to be true
    end
  end

  describe "autoloaded constants" do
    it "loads Token via autoload" do
      expect(described_class::Token).to eq(ApiClient::Jwt::Token)
    end

    it "loads JwksClient via autoload" do
      expect(described_class::JwksClient).to eq(ApiClient::Jwt::JwksClient)
    end

    it "loads KeyStore via autoload" do
      expect(described_class::KeyStore).to eq(ApiClient::Jwt::KeyStore)
    end

    it "loads Authenticator via autoload" do
      expect(described_class::Authenticator).to eq(ApiClient::Jwt::Authenticator)
    end
  end
end
