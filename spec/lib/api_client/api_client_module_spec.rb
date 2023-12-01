require "spec_helper"
require "api_client"

RSpec.describe ApiClient do
  describe ".configuration" do
    it "returns Configuration instance" do
      expect(described_class.configuration).to be_a(ApiClient::Configuration)
    end

    it "returns same instance on multiple calls" do
      first_call = described_class.configuration
      second_call = described_class.configuration
      expect(first_call.object_id).to eq(second_call.object_id)
    end
  end

  describe ".configure" do
    it "yields configuration" do
      described_class.configure do |config|
        expect(config).to be_a(ApiClient::Configuration)
      end
    end

    it "allows setting values" do
      described_class.configure { |c| c.read_timeout = 99 }
      expect(described_class.configuration.read_timeout).to eq(99)
    end
  end

  describe ".reset_configuration!" do
    it "creates new configuration" do
      original = described_class.configuration
      described_class.reset_configuration!
      expect(described_class.configuration).not_to eq(original)
    end

    it "resets to defaults" do
      described_class.configure { |c| c.read_timeout = 99 }
      described_class.reset_configuration!
      expect(described_class.configuration.read_timeout).to eq(30)
    end
  end

  describe ".new (Faraday-compatible)" do
    it "returns Base instance" do
      client = described_class.new
      expect(client).to be_a(ApiClient::Base)
    end

    it "accepts url: parameter (Faraday-style)" do
      client = described_class.new(url: "https://api.example.com")
      expect(client.config.service_uri).to eq("https://api.example.com")
    end

    it "accepts block configuration (Faraday-style)" do
      client = described_class.new(url: "https://api.example.com") do |config|
        config.read_timeout = 120
      end
      expect(client.config.read_timeout).to eq(120)
    end

    it "accepts service_uri: for backward compatibility" do
      client = described_class.new(service_uri: "https://legacy.example.com")
      expect(client.config.service_uri).to eq("https://legacy.example.com")
    end
  end

  describe ".default_adapter" do
    it "returns configured adapter" do
      expect(described_class.default_adapter).to be_a(Symbol)
    end

    it "can be set" do
      original = described_class.default_adapter
      described_class.default_adapter = :net_http
      expect(described_class.default_adapter).to eq(:net_http)
      described_class.default_adapter = original
    end
  end

  describe "module-level HTTP methods", :integration do
    before do
      described_class.configure do |c|
        c.service_uri = TestServerHolder.instance.base_url
      end
    end

    describe ".get" do
      it "makes GET request" do
        response = described_class.get("/health")
        expect(response).to be_a(Faraday::Response)
        expect(response.status).to eq(200)
      end

      it "accepts params" do
        response = described_class.get("/users", {page: 1})
        expect(response.status).to eq(200)
      end
    end

    describe ".post" do
      it "makes POST request" do
        response = described_class.post("/users", {name: "Test"})
        expect(response.status).to eq(201)
      end
    end

    describe ".put" do
      it "makes PUT request" do
        response = described_class.put("/echo", {name: "Updated"})
        expect(response.status).to eq(200)
      end
    end

    describe ".delete" do
      it "makes DELETE request" do
        response = described_class.delete("/echo")
        expect(response.status).to eq(200)
      end
    end
  end
end
