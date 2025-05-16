require "spec_helper"
require "api_client"

RSpec.describe ApiClient::RequestFlow, :fuzz, :integration do
  let(:client) { client_for_server }
  let(:request_flow) { client.request_flow }

  describe "request flow step fuzzing" do
    it "handles random transform chains" do
      property_of {
        depth = range(1, 3)
        depth.times.map { choose(:status, :body_size, :success) }
      }.check(20) do |transforms|
        p = client.request_flow.fetch(:get, "/health")

        transforms.each do |t|
          case t
          when :status then p.then { |r| r.respond_to?(:status) ? r.status : r }
          when :body_size then p.then { |r| r.respond_to?(:body) ? r.body.size : r.to_s.size }
          when :success then p.then { |r| r.respond_to?(:status) ? r.status == 200 : r }
          end
        end

        expect { p.collect }.not_to raise_error
      end
    end

    it "handles random filter predicates" do
      property_of { range(0, 10) }.check(10) do |threshold|
        result = client.request_flow
          .fetch(:get, "/users/1")
          .then { |r| JSON.parse(r.body)["post_ids"] }
          .filter { |id| id > threshold }
          .collect

        expect(result).to be_an(Array)
      end
    end

    it "handles empty fan-out gracefully" do
      result = client.request_flow
        .fetch(:get, "/users/1")
        .then { [] }
        .fan_out { |id| {method: :get, path: "/posts/#{id}"} }
        .collect

      expect(result).to eq([])
    end

    it "handles large fan-out" do
      result = client.request_flow
        .fetch(:get, "/users/1")
        .then { (1..20).to_a }
        .fan_out { |id| {method: :get, path: "/posts/#{id}"} }
        .collect

      expect(result.size).to eq(20)
    end
  end

  describe "request flow map fuzzing" do
    it "handles random map operations" do
      property_of {
        choose(:upcase, :downcase, :reverse, :strip)
      }.check(10) do |op|
        result = client.request_flow
          .fetch(:get, "/users/1")
          .then { |r| JSON.parse(r.body)["name"] }
          .then { |name| [name] }
          .map { |s| s.public_send(op) }
          .collect

        expect(result).to be_an(Array)
        expect(result.first).to be_a(String)
      end
    end
  end

  describe "request flow reset" do
    it "allows reuse after reset" do
      5.times do
        request_flow.reset
        result = request_flow
          .fetch(:get, "/health")
          .then { |r| r.status }
          .collect

        expect(result).to eq(200)
      end
    end
  end
end
