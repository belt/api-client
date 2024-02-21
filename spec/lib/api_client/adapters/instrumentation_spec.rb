require "spec_helper"
require "api_client"
require "api_client/adapters/base"
require "api_client/adapters/instrumentation"

RSpec.describe ApiClient::Adapters::Instrumentation do
  # Create a test class that includes the module
  let(:test_class) do
    Class.new do
      include ApiClient::Adapters::Base
      include ApiClient::Adapters::Instrumentation

      attr_reader :config

      def initialize(config)
        @config = config
      end

      def execute(requests)
        with_batch_instrumentation(:test_adapter, requests) { yield }
      end
    end
  end

  let(:config) { build(:api_client_configuration) }
  let(:adapter) { test_class.new(config) }

  describe "#with_batch_instrumentation" do
    let(:requests) { [{path: "/a"}, {path: "/b"}] }

    it "returns the block result" do
      responses = [double(status: 200), double(status: 201)]
      result = adapter.execute(requests) { responses }
      expect(result).to eq(responses)
    end

    it "instruments batch_start" do
      events = []
      subscriber = ApiClient::Hooks.subscribe(:batch_start) do |*args|
        events << ActiveSupport::Notifications::Event.new(*args)
      end

      adapter.execute(requests) { [] }

      expect(events.size).to eq(1)
      expect(events.first.payload).to include(adapter: :test_adapter, count: 2)
    ensure
      ApiClient::Hooks.unsubscribe(subscriber)
    end

    it "instruments batch_complete with success count" do
      events = []
      subscriber = ApiClient::Hooks.subscribe(:batch_complete) do |*args|
        events << ActiveSupport::Notifications::Event.new(*args)
      end

      responses = [double(status: 200), double(status: 500)]
      adapter.execute(requests) { responses }

      expect(events.size).to eq(1)
      payload = events.first.payload
      expect(payload[:adapter]).to eq(:test_adapter)
      expect(payload[:count]).to eq(2)
      expect(payload[:success_count]).to eq(1)
      expect(payload[:duration]).to be_a(Float)
    ensure
      ApiClient::Hooks.unsubscribe(subscriber)
    end

    it "counts success as status 200-299" do
      events = []
      subscriber = ApiClient::Hooks.subscribe(:batch_complete) do |*args|
        events << ActiveSupport::Notifications::Event.new(*args)
      end

      responses = [double(status: 200), double(status: 299), double(status: 300)]
      three_requests = [{}, {}, {}]
      adapter.execute(three_requests) { responses }

      expect(events.first.payload[:success_count]).to eq(2)
    ensure
      ApiClient::Hooks.unsubscribe(subscriber)
    end

    it "handles responses without status method" do
      events = []
      subscriber = ApiClient::Hooks.subscribe(:batch_complete) do |*args|
        events << ActiveSupport::Notifications::Event.new(*args)
      end

      responses = ["plain string"]
      adapter.execute([{}]) { responses }

      expect(events.first.payload[:success_count]).to eq(0)
    ensure
      ApiClient::Hooks.unsubscribe(subscriber)
    end

    it "instruments batch_slow when duration exceeds threshold" do
      events = []
      subscriber = ApiClient::Hooks.subscribe(:batch_slow) do |*args|
        events << ActiveSupport::Notifications::Event.new(*args)
      end

      # Set a very low threshold so any execution triggers it
      allow(config).to receive(:batch_slow_threshold_ms).and_return(0)

      adapter.execute(requests) { [double(status: 200)] }

      expect(events.size).to eq(1)
      expect(events.first.payload).to include(
        adapter: :test_adapter,
        count: 2,
        threshold_ms: 0
      )
    ensure
      ApiClient::Hooks.unsubscribe(subscriber)
    end

    it "does not instrument batch_slow when under threshold" do
      events = []
      subscriber = ApiClient::Hooks.subscribe(:batch_slow) do |*args|
        events << ActiveSupport::Notifications::Event.new(*args)
      end

      allow(config).to receive(:batch_slow_threshold_ms).and_return(999_999)

      adapter.execute(requests) { [double(status: 200)] }

      expect(events).to be_empty
    ensure
      ApiClient::Hooks.unsubscribe(subscriber)
    end
  end
end
