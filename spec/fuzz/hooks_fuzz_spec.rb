require "spec_helper"
require "api_client"

RSpec.describe "Hooks fuzzing", :fuzz do
  describe "concurrent registration and lookup" do
    it "handles rapid concurrent on() calls for same event" do
      config = ApiClient::Configuration.new
      barrier = Concurrent::CyclicBarrier.new(8)

      threads = 8.times.map do |t|
        Thread.new do
          barrier.wait
          10.times { |i| config.on(:shared_event) { |_| "t#{t}_h#{i}" } }
        end
      end

      threads.each(&:join)
      expect(config.hooks_for(:shared_event).size).to eq(80)
    end

    it "handles concurrent on() and hooks_for() without error" do
      config = ApiClient::Configuration.new
      barrier = Concurrent::CyclicBarrier.new(6)
      snapshots = Concurrent::Array.new

      writers = 3.times.map do |t|
        Thread.new do
          barrier.wait
          20.times { |i| config.on(:mixed_event) { |_| "w#{t}_#{i}" } }
        end
      end

      readers = 3.times.map do
        Thread.new do
          barrier.wait
          20.times { snapshots << config.hooks_for(:mixed_event).size }
        end
      end

      (writers + readers).each(&:join)

      # All snapshots should be non-negative integers
      expect(snapshots).to all(be >= 0)
      # Final count should be 60
      expect(config.hooks_for(:mixed_event).size).to eq(60)
    end
  end

  describe "hook dispatch with random payloads" do
    it "dispatches arbitrary payload hashes without error" do
      received = Concurrent::Array.new

      ApiClient.configure do |c|
        c.on(:request_complete) { |payload| received << payload }
      end

      property_of {
        dict(range(0, 5)) {
          [sized(10) { string(:alpha) }.to_sym, choose(integer, string, boolean, nil)]
        }
      }.check(10) do |payload|
        expect {
          ApiClient::Hooks.instrument(:request_complete, payload)
        }.not_to raise_error
      end

      expect(received.size).to eq(10)
    end
  end

  describe "safe_call resilience" do
    it "swallows various exception types from hooks" do
      exceptions = [
        RuntimeError.new("runtime"),
        ArgumentError.new("argument"),
        TypeError.new("type"),
        NoMethodError.new("no method"),
        ZeroDivisionError.new("zero div")
      ]

      exceptions.each do |exc|
        config = ApiClient::Configuration.new
        config.on(:test_event) { |_| raise exc }

        expect {
          ApiClient::Hooks.instrument(:test_event, {})
        }.not_to raise_error
      end
    end
  end
end
