require "spec_helper"
require "api_client"

RSpec.describe ApiClient::Hooks do
  describe "::NAMESPACE" do
    it "is api_client" do
      expect(described_class::NAMESPACE).to eq("api_client")
    end
  end

  describe "::EVENTS" do
    it "maps event symbols to names" do
      expect(described_class::EVENTS).to include(
        request_start: "request.start",
        request_complete: "request.complete"
      )
    end

    it "includes circuit_open event" do
      expect(described_class::EVENTS).to include(circuit_open: "circuit.open")
    end

    it "includes request_error event" do
      expect(described_class::EVENTS).to include(request_error: "request.error")
    end
  end

  describe ".instrument" do
    let(:payload) { {method: :get, url: "http://example.com"} }
    let(:events) { [] }
    let(:subscriber) do
      ActiveSupport::Notifications.subscribe("api_client.request.start") do |*args|
        events << ActiveSupport::Notifications::Event.new(*args)
      end
    end

    after { ActiveSupport::Notifications.unsubscribe(subscriber) }

    it "publishes to ActiveSupport::Notifications" do
      subscriber
      described_class.instrument(:request_start, payload)
      expect(events.size).to eq(1)
    end

    it "includes payload in published event" do
      subscriber
      described_class.instrument(:request_start, payload)
      expect(events.first.payload).to include(method: :get)
    end

    it "dispatches custom hooks from configuration" do
      called = false
      ApiClient.configure { |c| c.on(:request_start) { |_| called = true } }
      described_class.instrument(:request_start, payload)
      expect(called).to be true
    end

    it "handles hook errors gracefully" do
      ApiClient.configure do |c|
        c.on(:request_start) { |_| raise "Hook error" }
        c.logger = Logger.new(File::NULL)
      end
      expect { described_class.instrument(:request_start, payload) }.not_to raise_error
    end
  end

  describe ".subscribe" do
    let(:events) { [] }
    let(:subscriber) { described_class.subscribe(:request_complete) { |*args| events << args } }

    after { described_class.unsubscribe(subscriber) }

    it "subscribes to namespaced events" do
      subscriber
      ActiveSupport::Notifications.instrument("api_client.request.complete", {})
      expect(events).not_to be_empty
    end
  end

  describe ".unsubscribe" do
    it "removes subscription" do
      events = []
      subscriber = described_class.subscribe(:request_complete) { |*args| events << args }
      described_class.unsubscribe(subscriber)
      ActiveSupport::Notifications.instrument("api_client.request.complete", {})
      expect(events).to be_empty
    end
  end
end
