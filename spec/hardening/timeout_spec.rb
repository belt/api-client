require "spec_helper"
require "api_client"

RSpec.describe ApiClient::Base, :integration do # rubocop:disable RSpec/SpecFilePathFormat
  describe "timeout behavior" do
    describe "read timeout" do
      let(:client) do
        client_for_mock_api(adapter: :net_http, read_timeout: 0.1, retry: {max: 0})
      end

      it "raises on slow response" do
        stub_request(:get, "#{client.config.service_uri}/delay/1")
          .to_raise(Faraday::TimeoutError.new("simulated read timeout"))

        expect { client.get("/delay/1") }.to raise_error(Faraday::TimeoutError, /simulated read timeout/)
      end

      it "succeeds within timeout" do
        stub_request(:get, "#{client.config.service_uri}/delay/0.05")
          .to_return(status: 200, body: {delayed: 0.05}.to_json)

        response = client.get("/delay/0.05")
        expect(response.status).to eq(200)
      end
    end

    describe "timeout configuration" do
      it "accepts open_timeout" do
        config = build(:api_client_configuration, open_timeout: 1)
        expect(config.open_timeout).to eq(1)
      end

      it "accepts read_timeout" do
        config = build(:api_client_configuration, read_timeout: 1)
        expect(config.read_timeout).to eq(1)
      end

      it "accepts write_timeout" do
        config = build(:api_client_configuration, write_timeout: 1)
        expect(config.write_timeout).to eq(1)
      end
    end

    describe "timeout edge cases" do
      let(:client) do
        client_for_mock_api(adapter: :net_http, read_timeout: 0.2, retry: {max: 0})
      end

      it "handles timeout at boundary" do # rubocop:disable RSpec/ExampleLength
        stub_request(:get, "#{client.config.service_uri}/delay/0.2")
          .to_raise(Faraday::TimeoutError.new("simulated boundary timeout"))

        expect { client.get("/delay/0.2") }.to raise_error(Faraday::TimeoutError)
      end
    end
  end
end
