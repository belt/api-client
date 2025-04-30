require "spec_helper"
require "api_client"

RSpec.describe "Error handling fuzzing", :fuzz, :integration do
  let(:client) { client_for_server }

  describe "HTTP error status fuzzing" do
    let(:client) { client_for_server(retry: {max: 0}) }

    it "handles random 4xx errors gracefully" do
      [400, 401, 403, 404, 405, 409, 422].each do |status|
        response = client.get("/error/#{status}")
        expect(response.status).to eq(status)
      end
    end

    it "handles random 5xx errors gracefully" do
      [500, 501, 502].each do |status|
        response = client.get("/error/#{status}")
        expect(response.status).to eq(status)
      end
    end
  end

  describe "batch error handling" do
    it "handles mixed success and error responses" do
      property_of { array(5) { range(200, 504) } }.check(10) do |statuses|
        requests = statuses.map do |status|
          path = (status >= 400) ? "/error/#{status}" : "/health"
          {method: :get, path: path}
        end

        responses = client.batch(requests)
        expect(responses.size).to eq(5)

        responses.each_with_index do |r, i|
          expected = (statuses[i] >= 400) ? statuses[i] : 200
          expect(r.status).to eq(expected)
        end
      end
    end

    it "handles all-error batches" do
      requests = 5.times.map { {method: :get, path: "/error/500"} }
      responses = client.batch(requests)

      expect(responses).to all(have_attributes(status: 500))
    end
  end

  describe "circuit breaker error accumulation" do
    it "tracks failures correctly under random error patterns" do
      property_of {
        array(10) { choose(200, 500) }
      }.check(5) do |pattern|
        test_client = client_for_server
        test_client.config.circuit.threshold = 100 # High threshold to avoid opening

        pattern.each do |status|
          path = (status == 500) ? "/error/500" : "/health"
          test_client.get(path)
        rescue
          nil
        end

        expected_failures = pattern.count(500)
        expect(test_client.circuit.failure_count).to eq(expected_failures)
      end
    end
  end

  describe "timeout error handling" do
    let(:client) do
      client_for_server(adapter: :net_http, read_timeout: 0.5, retry: {max: 0})
    end

    it "raises timeout for slow endpoints" do
      expect { client.get("/delay/2") }.to raise_error(Faraday::TimeoutError)
    end

    it "succeeds for fast endpoints" do
      response = client.get("/delay/0.1")
      expect(response.status).to eq(200)
    end
  end
end
