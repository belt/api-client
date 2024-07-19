require "spec_helper"
require "api_client"

# Integration tests for request flow chaining — examples are inherently
# multi-step and multi-assertion due to the pipeline nature.
# rubocop:disable RSpec/ExampleLength, RSpec/MultipleExpectations
RSpec.describe ApiClient::RequestFlow, :integration do
  subject(:request_flow) { described_class.new(connection) }

  let(:config) { build(:api_client_configuration, service_uri: base_url) }
  let(:connection) { ApiClient::Connection.new(config) }

  describe "#initialize" do
    it "sets connection" do
      expect(request_flow.connection).to eq(connection)
    end

    it "initializes empty steps" do
      expect(request_flow.steps).to eq([])
    end
  end

  describe "#fetch" do
    it "adds fetch step" do
      request_flow.fetch(:get, "/users/1")
      expect(request_flow.steps.size).to eq(1)
      expect(request_flow.steps.first.first).to eq(:fetch)
    end

    it "returns self for chaining" do
      expect(request_flow.fetch(:get, "/users/1")).to eq(request_flow)
    end
  end

  describe "#then" do
    it "adds transform step" do
      request_flow.then { |r| r }
      expect(request_flow.steps.first.first).to eq(:transform)
    end

    it "returns self for chaining" do
      expect(request_flow.then { |r| r }).to eq(request_flow)
    end
  end

  describe "#fan_out" do
    it "adds fan_out step" do
      request_flow.fan_out { |id| {method: :get, path: "/posts/#{id}"} }
      expect(request_flow.steps.first.first).to eq(:fan_out)
    end

    it "returns self for chaining" do
      result = request_flow.fan_out { |id| {method: :get, path: "/posts/#{id}"} }
      expect(result).to eq(request_flow)
    end
  end

  describe "#filter" do
    it "adds filter step" do
      request_flow.filter { |x| x > 0 }
      expect(request_flow.steps.first.first).to eq(:filter)
    end
  end

  describe "#map" do
    it "adds map step" do
      request_flow.map { |x| x * 2 }
      expect(request_flow.steps.first.first).to eq(:map)
    end
  end

  describe "#parallel_map" do
    it "adds parallel_map step" do
      request_flow.parallel_map
      expect(request_flow.steps.first.first).to eq(:parallel_map)
    end

    it "stores options" do
      recipe = ApiClient::Transforms::Recipe.new(extract: :body, transform: :sha256)
      errors = ApiClient::Processing::ErrorStrategy.skip
      request_flow.parallel_map(recipe: recipe, errors: errors)
      opts = request_flow.steps.first.last
      expect(opts).to include(recipe: recipe, errors: errors)
    end

    it "returns self for chaining" do
      expect(request_flow.parallel_map).to eq(request_flow)
    end
  end

  describe "#collect" do
    context "with simple fetch" do
      it "executes fetch and returns response" do
        result = request_flow
          .fetch(:get, "/users/1")
          .collect

        expect(result).to be_a(Faraday::Response)
        expect(result.status).to eq(200)
      end
    end

    context "with fetch and transform" do
      it "transforms response" do
        result = request_flow
          .fetch(:get, "/users/1")
          .then { |r| JSON.parse(r.body) }
          .then { |data| data["id"] }
          .collect

        expect(result).to eq(1)
      end
    end

    context "with user -> posts request flow" do
      it "fetches user then fans out to posts" do
        results = request_flow
          .fetch(:get, "/users/1")
          .then { |r| JSON.parse(r.body)["post_ids"] }
          .fan_out { |id| {method: :get, path: "/posts/#{id}"} }
          .collect

        expect(results).to be_an(Array)
        expect(results.size).to eq(3) # User 1 has post_ids [11, 12, 13]
        expect(results).to all(be_a(Faraday::Response))
      end

      it "can transform fan_out results" do
        results = request_flow
          .fetch(:get, "/users/1")
          .then { |r| JSON.parse(r.body)["post_ids"] }
          .fan_out { |id| {method: :get, path: "/posts/#{id}"} }
          .map { |r| JSON.parse(r.body)["title"] }
          .collect

        expect(results).to all(be_a(String))
        expect(results).to all(start_with("Post"))
      end

      it "can parallel_map fan_out results" do
        results = request_flow
          .fetch(:get, "/users/1")
          .then { |r| JSON.parse(r.body)["post_ids"] }
          .fan_out { |id| {method: :get, path: "/posts/#{id}"} }
          .parallel_map
          .collect

        expect(results).to all(be_a(Hash))
        expect(results.map { |r| r["id"] }).to eq([11, 12, 13])
      end

      it "can chain parallel_map with block" do
        results = request_flow
          .fetch(:get, "/users/1")
          .then { |r| JSON.parse(r.body)["post_ids"] }
          .fan_out { |id| {method: :get, path: "/posts/#{id}"} }
          .parallel_map { |parsed| parsed["title"] }
          .collect

        expect(results).to all(start_with("Post"))
      end
    end

    context "with filter" do
      it "filters items" do
        result = request_flow
          .fetch(:get, "/users/1")
          .then { |r| JSON.parse(r.body)["post_ids"] }
          .filter { |id| id > 11 }
          .collect

        expect(result).to eq([12, 13])
      end
    end

    context "with empty fan_out" do
      it "returns empty array" do
        result = request_flow
          .fetch(:get, "/users/1")
          .then { |_| [] }
          .fan_out { |id| {method: :get, path: "/posts/#{id}"} }
          .collect

        expect(result).to eq([])
      end
    end
  end

  describe "#reset" do
    it "clears steps" do
      request_flow.fetch(:get, "/users/1")
      request_flow.reset
      expect(request_flow.steps).to eq([])
    end

    it "returns self" do
      expect(request_flow.reset).to eq(request_flow)
    end

    it "allows reuse" do
      result1 = request_flow.fetch(:get, "/users/1").collect
      request_flow.reset
      result2 = request_flow.fetch(:get, "/users/2").collect

      body1 = JSON.parse(result1.body)
      body2 = JSON.parse(result2.body)

      expect(body1["id"]).to eq(1)
      expect(body2["id"]).to eq(2)
    end
  end

  describe "#async_map" do
    it "adds async_map step" do
      request_flow.async_map
      expect(request_flow.steps.first.first).to eq(:async_map)
    end

    it "stores options" do
      recipe = ApiClient::Transforms::Recipe.status
      errors = ApiClient::Processing::ErrorStrategy.skip
      request_flow.async_map(recipe: recipe, errors: errors)
      opts = request_flow.steps.first.last
      expect(opts).to include(recipe: recipe, errors: errors)
    end

    it "returns self for chaining" do
      expect(request_flow.async_map).to eq(request_flow)
    end
  end

  describe "#concurrent_map" do
    it "adds concurrent_map step" do
      request_flow.concurrent_map
      expect(request_flow.steps.first.first).to eq(:concurrent_map)
    end

    it "stores options" do
      errors = ApiClient::Processing::ErrorStrategy.replace({})
      request_flow.concurrent_map(errors: errors)
      opts = request_flow.steps.first.last
      expect(opts).to include(errors: errors)
    end

    it "returns self for chaining" do
      expect(request_flow.concurrent_map).to eq(request_flow)
    end
  end

  describe "#process" do
    it "adds process step" do
      request_flow.process
      expect(request_flow.steps.first.first).to eq(:process)
    end

    it "stores options" do
      recipe = ApiClient::Transforms::Recipe.new(extract: :body, transform: :sha256)
      errors = ApiClient::Processing::ErrorStrategy.fail_fast
      request_flow.process(recipe: recipe, errors: errors)
      opts = request_flow.steps.first.last
      expect(opts).to include(recipe: recipe, errors: errors)
    end

    it "returns self for chaining" do
      expect(request_flow.process).to eq(request_flow)
    end
  end

  describe "#collect with processor steps" do
    context "with async_map" do
      it "processes fan_out results with async processor" do
        results = request_flow
          .fetch(:get, "/users/1")
          .then { |r| JSON.parse(r.body)["post_ids"] }
          .fan_out { |id| {method: :get, path: "/posts/#{id}"} }
          .async_map
          .collect

        expect(results).to all(be_a(Hash))
        expect(results.map { |r| r["id"] }).to eq([11, 12, 13])
      end
    end

    context "with concurrent_map" do
      it "processes fan_out results with concurrent processor" do
        results = request_flow
          .fetch(:get, "/users/1")
          .then { |r| JSON.parse(r.body)["post_ids"] }
          .fan_out { |id| {method: :get, path: "/posts/#{id}"} }
          .concurrent_map
          .collect

        expect(results).to all(be_a(Hash))
        expect(results.map { |r| r["id"] }).to eq([11, 12, 13])
      end
    end

    context "with process (auto-detect)" do
      it "processes fan_out results with auto-detected processor" do
        results = request_flow
          .fetch(:get, "/users/1")
          .then { |r| JSON.parse(r.body)["post_ids"] }
          .fan_out { |id| {method: :get, path: "/posts/#{id}"} }
          .process
          .collect

        expect(results).to all(be_a(Hash))
        expect(results.map { |r| r["id"] }).to eq([11, 12, 13])
      end
    end

    context "with unknown step type" do
      it "raises ApiClient::Error for unregistered step" do
        # Manually inject an unknown step
        request_flow.instance_variable_get(:@steps) << [:unknown_step, {}]
        expect { request_flow.collect }.to raise_error(ApiClient::Error, /Unknown request flow step/)
      end
    end
  end

  describe "hooks integration" do
    it "instruments request_flow_start" do
      events = []
      subscriber = ApiClient::Hooks.subscribe(:request_flow_start) do |*args|
        events << ActiveSupport::Notifications::Event.new(*args)
      end

      request_flow.fetch(:get, "/users/1").collect

      expect(events.size).to eq(1)
      expect(events.first.payload).to include(step_count: 1)
    ensure
      ApiClient::Hooks.unsubscribe(subscriber)
    end

    it "instruments request_flow_step" do
      events = []
      subscriber = ApiClient::Hooks.subscribe(:request_flow_step) do |*args|
        events << ActiveSupport::Notifications::Event.new(*args)
      end

      request_flow.fetch(:get, "/users/1").then { |r| r }.collect

      expect(events.size).to eq(2)
      expect(events.first.payload[:step_type]).to eq(:fetch)
      expect(events.last.payload[:step_type]).to eq(:transform)
    ensure
      ApiClient::Hooks.unsubscribe(subscriber)
    end

    it "instruments request_flow_complete" do
      events = []
      subscriber = ApiClient::Hooks.subscribe(:request_flow_complete) do |*args|
        events << ActiveSupport::Notifications::Event.new(*args)
      end

      request_flow.fetch(:get, "/users/1").collect

      expect(events.size).to eq(1)
      expect(events.first.payload).to include(step_count: 1)
      expect(events.first.payload[:duration]).to be_a(Float)
    ensure
      ApiClient::Hooks.unsubscribe(subscriber)
    end
  end
end
# rubocop:enable RSpec/ExampleLength, RSpec/MultipleExpectations
