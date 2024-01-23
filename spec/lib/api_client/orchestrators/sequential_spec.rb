require "spec_helper"
require "api_client"

RSpec.describe ApiClient::Orchestrators::Sequential, :integration do
  subject(:executor) { described_class.new(connection) }

  let(:config) { build(:api_client_configuration, service_uri: base_url) }
  let(:connection) { ApiClient::Connection.new(config) }

  describe "#initialize" do
    it "sets connection" do
      expect(executor.connection).to eq(connection)
    end
  end

  it_behaves_like "executor execute behavior"

  describe "#execute" do
    context "with sequential ordering" do
      let(:requests) { 3.times.map { |i| {method: :get, path: "/users/#{i + 1}", params: {seq: i}} } }

      before { test_server.clear_requests }

      it "executes in order" do
        executor.execute(requests)
        paths = test_server.requests.map { |r| r[:path].split("?").first }
        expect(paths).to eq(["/users/1", "/users/2", "/users/3"])
      end
    end

    context "with params and headers" do
      let(:requests) { [{method: :get, path: "/echo", params: {page: 1}, headers: {"X-Test" => "value"}}] }

      it "passes params and headers" do
        response = executor.execute(requests).first
        body = JSON.parse(response.body)
        expect(body["headers"]).to include("X-Test" => "value")
      end
    end

    context "with POST body" do
      it "sends body" do
        requests = [{method: :post, path: "/users", body: {name: "Test User"}}]
        response = executor.execute(requests).first
        body = JSON.parse(response.body)
        expect(body["name"]).to eq("Test User")
      end
    end

    context "with mixed success and failure" do
      let(:requests) do
        [
          {method: :get, path: "/users/1"},
          {method: :get, path: "/error/404"},
          {method: :get, path: "/users/2"}
        ]
      end

      it "returns all responses including errors" do
        expect(executor.execute(requests).map(&:status)).to eq([200, 404, 200])
      end
    end
  end
end
