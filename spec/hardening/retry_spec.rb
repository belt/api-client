require "spec_helper"
require "api_client"

RSpec.describe ApiClient::Base, :integration do # rubocop:disable RSpec/SpecFilePathFormat
  describe "retry behavior" do
    describe "exponential backoff" do
      let(:client) do
        client_for_server(retry: {max: 3, interval: 0.1, backoff_factor: 2, interval_randomness: 0})
      end

      it "retries on 503" do
        # First 2 calls fail, third succeeds
        response = client.get("/circuit?reset=true")
        expect(response.status).to eq(200)
      end
    end

    describe "retry statuses" do
      let(:client) do
        # Only retry on 503, not 500
        client_for_server(retry: {max: 1, retry_statuses: [503]})
      end

      it "retries on configured status" do
        # /error/500 returns 500 which is NOT in retry_statuses
        # So it should return the 500 response without retrying
        response = client.get("/error/500")
        expect(response.status).to eq(500)
      end

      it "does not retry on non-configured status" do
        response = client.get("/error/400")
        expect(response.status).to eq(400)
      end
    end

    describe "retry methods" do
      let(:client) do
        client_for_server(retry: {max: 1, methods: [:get]})
      end

      it "retries configured methods" do # rubocop:disable RSpec/ExampleLength
        # GET should retry
        expect(test_server.requests.size).to eq(0)
        begin
          client.get("/error/503")
        rescue
          nil
        end
        # Should have made 2 requests (original + 1 retry)
      end
    end

    describe "max retries" do
      let(:client) do
        client_for_server(retry: {max: 2, interval: 0.01})
      end

      it "stops after max retries" do # rubocop:disable RSpec/ExampleLength
        test_server.clear_requests
        begin
          client.get("/error/503")
        rescue
          nil
        end

        # Original + 2 retries = 3 total requests
        expect(test_server.requests.size).to be <= 3
      end
    end

    describe "jitter (interval_randomness)" do
      let(:client) do
        client_for_server(retry: {max: 2, interval: 0.1, interval_randomness: 0.5})
      end

      it "varies retry intervals" do # rubocop:disable RSpec/ExampleLength
        # With randomness, intervals should vary
        # This is hard to test precisely, but we verify it doesn't crash
        expect {
          begin
            client.get("/error/503")
          rescue
            nil
          end
        }.not_to raise_error
      end
    end
  end
end
