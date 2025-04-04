require "spec_helper"
require "api_client"

RSpec.describe "Hooks thread safety", :integration do
  describe "concurrent hook registration and dispatch" do
    it "handles concurrent on() registration without corruption" do
      config = ApiClient::Configuration.new
      barrier = Concurrent::CyclicBarrier.new(10)

      threads = 10.times.map do |i|
        Thread.new do
          barrier.wait
          20.times { |j| config.on(:"event_#{i}") { |_| "hook_#{i}_#{j}" } }
        end
      end

      threads.each(&:join)

      10.times do |i|
        expect(config.hooks_for(:"event_#{i}").size).to eq(20)
      end
    end

    it "hooks_for returns frozen snapshot safe for iteration" do
      config = ApiClient::Configuration.new
      config.on(:test_event) { |_| "a" }
      config.on(:test_event) { |_| "b" }

      snapshot = config.hooks_for(:test_event)
      expect(snapshot).to be_frozen
      expect(snapshot.size).to eq(2)
    end

    it "hooks returns a dup that does not affect internal state" do
      config = ApiClient::Configuration.new
      config.on(:test_event) { |_| "a" }

      external = config.hooks
      external[:test_event] = []

      expect(config.hooks_for(:test_event).size).to eq(1)
    end

    it "dispatches hooks concurrently without errors" do
      counter = Concurrent::AtomicFixnum.new(0)
      ApiClient.configure { |c| c.on(:request_complete) { |_| counter.increment } }

      client = client_for_server
      barrier = Concurrent::CyclicBarrier.new(5)

      threads = 5.times.map do
        Thread.new do
          barrier.wait
          3.times { client.get("/health") }
        end
      end

      threads.each(&:join)
      expect(counter.value).to eq(15)
    end
  end

  describe "safe_call error isolation" do
    before do
      logger = ApiClient.configuration.logger
      logger.level = Logger::FATAL if logger
    end

    it "logs and swallows hook errors without affecting request" do
      ApiClient.configure do |c|
        c.on(:request_complete) { |_| raise "boom" }
      end

      client = client_for_server
      response = client.get("/health")
      expect(response.status).to eq(200)
    end

    it "continues dispatching remaining hooks after one fails" do
      called = Concurrent::AtomicBoolean.new(false)

      ApiClient.configure do |c|
        c.on(:request_complete) { |_| raise "first hook fails" }
        c.on(:request_complete) { |_| called.make_true }
      end

      client = client_for_server
      client.get("/health")
      expect(called.value).to be true
    end
  end
end
