require "spec_helper"

RSpec.describe "Adapter performance", :benchmark, :integration do
  let(:request_count) { 10 }
  let(:requests) do
    request_count.times.map { |i| {method: :get, path: "/users/#{i + 1}"} }
  end

  describe "parallel adapter comparison" do
    it "compares adapter throughput" do
      skip "Typhoeus not available" unless defined?(::Typhoeus)
      skip "Async not available" unless defined?(::Async)

      async_adapter = ApiClient::Adapters::AsyncAdapter.new(
        build(:api_client_configuration, service_uri: base_url)
      )
      concurrent_adapter = ApiClient::Adapters::Concurrent.new(
        build(:api_client_configuration, service_uri: base_url)
      )
      typhoeus_adapter = ApiClient::Adapters::Typhoeus.new(
        build(:api_client_configuration, service_uri: base_url)
      )

      compare_performance do |x|
        x.report("async") { async_adapter.execute(requests) }
        x.report("concurrent") { concurrent_adapter.execute(requests) }
        x.report("typhoeus") { typhoeus_adapter.execute(requests) }
      end
    end
  end

  describe "sequential vs batch" do
    it "compares execution strategies" do
      client = client_for_server

      compare_performance do |x|
        x.report("sequential") { client.sequential(requests) }
        x.report("batch") { client.batch(requests) }
      end
    end
  end

  describe "single request overhead" do
    it "measures single request latency" do
      client = client_for_server
      single_request = [{method: :get, path: "/health"}]

      compare_performance do |x|
        x.report("direct") { client.get("/health") }
        x.report("sequential") { client.sequential(single_request) }
        x.report("batch") { client.batch(single_request) }
      end
    end
  end
end
