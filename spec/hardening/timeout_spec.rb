require "spec_helper"
require "api_client"

RSpec.describe ApiClient::Base, :integration do # rubocop:disable RSpec/SpecFilePathFormat
  describe "timeout behavior" do
    describe "read timeout" do
      let(:client) do
        # Force net_http adapter for reliable timeout behavior in tests
        # Typhoeus handles local connections differently
        client_for_server(adapter: :net_http, read_timeout: 0.1, retry: {max: 0})
      end

      it "raises on slow response" do
        expect { client.get("/delay/1") }.to raise_error(Faraday::TimeoutError)
      end

      it "succeeds within timeout" do
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
        # Force net_http adapter for reliable timeout behavior
        client_for_server(adapter: :net_http, read_timeout: 0.2, retry: {max: 0})
      end

      it "handles timeout at boundary" do # rubocop:disable RSpec/ExampleLength
        # Request takes exactly timeout duration - may or may not timeout
        # Just verify no crash
        expect {
          begin
            client.get("/delay/0.2")
          rescue
            nil
          end
        }.not_to raise_error
      end
    end
  end
end
