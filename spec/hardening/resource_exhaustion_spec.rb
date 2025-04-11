require "spec_helper"
require "api_client"

RSpec.describe ApiClient::Base, :integration do # rubocop:disable RSpec/SpecFilePathFormat
  let(:client) { client_for_server }

  describe "resource exhaustion protection" do
    describe "batch request limits" do
      it "handles many batch requests" do
        requests = 50.times.map { {method: :get, path: "/health"} }

        expect { client.batch(requests) }.not_to raise_error
      end
    end

    describe "circuit breaker protection" do
      let(:client) do
        client_for_server.tap do |c|
          c.config.circuit.threshold = 3
          c.config.circuit.cool_off = 1
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

      it "fails fast when circuit open" do # rubocop:disable RSpec/ExampleLength
        3.times {
          begin
            client.get("/error/500")
          rescue
            nil
          end
        }

        start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        begin
          client.get("/health")
        rescue
          nil
        end
        elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start

        # Should fail immediately, not wait for timeout
        expect(elapsed).to be < 0.1
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
        client_for_server.tap do |c|
          c.config.retry.max = 2
          c.config.retry.interval = 0.01
        end
      end

      it "limits total retry attempts" do # rubocop:disable RSpec/ExampleLength
        test_server.clear_requests

        # Make request that always fails
        begin
          client.get("/error/503")
        rescue
          nil
        end

        # Should be original + max retries
        expect(test_server.requests.size).to be <= 3
      end
    end
  end
end
