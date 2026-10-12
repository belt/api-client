require "spec_helper"
require "api_client"

RSpec.describe ApiClient::Base do # rubocop:disable RSpec/SpecFilePathFormat
  let(:service_uri) { "http://resource-exhaustion-#{SecureRandom.hex(4)}.example.test" }
  let(:client) { described_class.new(service_uri: service_uri) }

  let(:health_request) do
    stub_request(:get, "#{service_uri}/health").to_return(status: 200, body: "ok")
  end

  let(:request_counts) { Hash.new(0) }

  before do
    health_request
    stub_request(:get, "#{service_uri}/error/500").to_return(status: 500, body: "error")
    stub_request(:get, "#{service_uri}/error/503").to_return do
      request_counts[:unavailable] += 1
      {status: 503, body: "error"}
    end
  end

  describe "resource exhaustion protection" do
    describe "batch request limits" do
      it "handles many batch requests" do
        requests = 50.times.map { {method: :get, path: "/health"} }

        expect { client.batch(requests) }.not_to raise_error
      end
    end

    describe "circuit breaker protection" do
      let(:client) do
        described_class.new(
          service_uri: service_uri,
          retry: {interval: 0.001, interval_randomness: 0}
        ).tap do |c|
          c.config.circuit.threshold = 3
          c.config.circuit.cool_off = 60
        end
      end

      it "opens circuit after threshold failures" do # rubocop:disable RSpec/ExampleLength
        3.times {
          begin
            client.get("/error/500")
          rescue
            nil
          end
        }

        expect(client.circuit_open?).to be true
      end

      it "fails fast when circuit open" do # rubocop:disable RSpec/ExampleLength,RSpec/MultipleExpectations
        3.times {
          begin
            client.get("/error/500")
          rescue
            nil
          end
        }
        expect(client.circuit_open?).to be true

        expect { client.get("/health") }.to raise_error(ApiClient::CircuitOpenError)
        expect(health_request).not_to have_been_requested
      end

      it "recovers after cool_off period" do # rubocop:disable RSpec/ExampleLength
        3.times {
          begin
            client.get("/error/500")
          rescue
            nil
          end
        }

        Timecop.freeze(Time.now + 2) do
          # Circuit should be half-open, allowing probe
          client.reset_circuit!
          response = client.get("/health")
          expect(response.status).to eq(200)
        end
      end
    end

    describe "retry amplification protection" do
      let(:client) do
        described_class.new(
          service_uri: service_uri,
          retry: {max: 2, interval: 0.01}
        )
      end

      it "limits total retry attempts" do # rubocop:disable RSpec/ExampleLength,RSpec/MultipleExpectations
        expect { client.get("/error/503") }.to raise_error(Faraday::RetriableResponse)

        expect(request_counts[:unavailable]).to be_between(1, 3).inclusive
      end
    end
  end
end
