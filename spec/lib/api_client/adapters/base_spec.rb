require "spec_helper"
require "api_client"
require "api_client/adapters/base"

RSpec.describe ApiClient::Adapters::Base do
  let(:test_class) do
    Class.new do
      include ApiClient::Adapters::Base

      def config
        ApiClient.configuration
      end
    end
  end

  let(:instance) { test_class.new }

  describe "ERROR_CLASS_HEADER (via ResponseBuilder)" do
    it "is frozen" do
      expect(ApiClient::ResponseBuilder::ERROR_CLASS_HEADER).to be_frozen
    end

    it "equals X-Error-Class" do
      expect(ApiClient::ResponseBuilder::ERROR_CLASS_HEADER).to eq("X-Error-Class")
    end
  end

  describe "#encode_body" do
    it "returns nil for nil body" do
      expect(instance.encode_body(nil)).to be_nil
    end

    it "returns string body unchanged" do
      expect(instance.encode_body("already a string")).to eq("already a string")
    end

    it "encodes hash to JSON" do
      result = instance.encode_body({key: "value"})
      expect(result).to eq('{"key":"value"}')
    end

    it "encodes array to JSON" do
      result = instance.encode_body([1, 2, 3])
      expect(result).to eq("[1,2,3]")
    end
  end

  describe "#build_error_response" do
    let(:error) { StandardError.new("Something went wrong") }
    let(:uri) { "https://api.example.com/path" }

    it "returns Faraday::Response" do
      response = instance.build_error_response(error, uri)
      expect(response).to be_a(Faraday::Response)
    end

    it "sets status to 0" do
      response = instance.build_error_response(error, uri)
      expect(response.status).to eq(0)
    end

    it "sets error class header" do
      response = instance.build_error_response(error, uri)
      expect(response.headers["X-Error-Class"]).to eq("StandardError")
    end

    it "sets body to error message" do
      response = instance.build_error_response(error, uri)
      expect(response.body).to eq("Something went wrong")
    end

    it "sets url from string" do
      response = instance.build_error_response(error, uri)
      expect(response.env.url.to_s).to eq(uri)
    end

    it "sets url from URI object" do
      uri_obj = URI.parse(uri)
      response = instance.build_error_response(error, uri_obj)
      expect(response.env.url).to eq(uri_obj)
    end

    it "instruments request_error" do
      events = []
      subscriber = ApiClient::Hooks.subscribe(:request_error) do |*args|
        events << ActiveSupport::Notifications::Event.new(*args)
      end

      instance.build_error_response(error, uri)

      expect(events.size).to eq(1)
      expect(events.first.payload).to include(url: uri, error: error)
    ensure
      ApiClient::Hooks.unsubscribe(subscriber)
    end
  end

  describe "#merged_headers" do
    before do
      ApiClient.configure do |config|
        config.default_headers = {"X-Default" => "value", "Content-Type" => "application/json"}
      end
    end

    it "returns default headers when nil passed" do
      result = instance.merged_headers(nil)
      expect(result).to include("X-Default" => "value")
    end

    it "returns default headers when empty hash passed" do
      result = instance.merged_headers({})
      expect(result).to include("X-Default" => "value")
    end

    it "merges request headers with defaults" do
      result = instance.merged_headers({"X-Custom" => "custom"})
      expect(result).to include("X-Default" => "value", "X-Custom" => "custom")
    end

    it "request headers override defaults" do
      result = instance.merged_headers({"Content-Type" => "text/plain"})
      expect(result["Content-Type"]).to eq("text/plain")
    end
  end
end
