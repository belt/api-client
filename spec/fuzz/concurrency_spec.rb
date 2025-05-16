require "spec_helper"
require "api_client"
require "async"

RSpec.describe ApiClient::Base, :fuzz, :integration do
  let(:client) { client_for_server }

  def run_concurrent_tasks(count, &block)
    Sync do |task|
      tasks = count.times.map { task.async(&block) }
      tasks.map(&:wait)
    end
  end

  describe "concurrency safety" do
    it "handles concurrent batch calls" do
      results = run_concurrent_tasks(5) do
        requests = 3.times.map { {method: :get, path: "/health"} }
        client.batch(requests)
      end

      results.each { |responses| expect(responses.size).to eq(3) }
    end

    it "maintains response order under concurrency" do
      requests = [
        {method: :get, path: "/users/1"},
        {method: :get, path: "/users/2"},
        {method: :get, path: "/users/3"}
      ]

      results = run_concurrent_tasks(10) do
        client.batch(requests).map { |r| JSON.parse(r.body)["id"] }
      end

      expect(results).to all(eq([1, 2, 3]))
    end
  end

  describe "circuit breaker fiber safety" do
    before { client.config.circuit.threshold = 5 }

    it "handles concurrent circuit state changes" do
      run_concurrent_tasks(10) do
        5.times {
          begin
            client.get("/error/500")
          rescue
            nil
          end
        }
      end

      expect(client.circuit_open?).to be true
    end

    it "handles concurrent reset calls" do
      client.config.circuit.threshold = 2
      2.times {
        begin
          client.get("/error/500")
        rescue
          nil
        end
      }

      expect { run_concurrent_tasks(5) { client.reset_circuit! } }.not_to raise_error
    end
  end

  describe "configuration fiber safety" do
    it "handles concurrent configuration reads" do
      expect do
        run_concurrent_tasks(20) do
          100.times do
            ApiClient.configuration.read_timeout
            ApiClient.configuration.service_uri
          end
        end
      end.not_to raise_error
    end
  end

  describe "hooks fiber safety" do
    it "handles concurrent hook dispatch" do
      counter = Concurrent::AtomicFixnum.new(0)
      ApiClient.configure { |config| config.on(:request_complete) { |_| counter.increment } }

      run_concurrent_tasks(10) { 5.times { client.get("/health") } }

      expect(counter.value).to eq(50)
    end
  end
end
