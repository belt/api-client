# Benchmark configuration for performance testing
#
# Uses benchmark-ips for iterations/second comparisons.
#
# Usage in specs:
#   it "compares adapters", :benchmark do
#     compare_performance do |x|
#       x.report("async") { async_adapter.execute(requests) }
#       x.report("concurrent") { concurrent_adapter.execute(requests) }
#     end
#   end

require "benchmark"
require "benchmark/ips"

module Support
  module BenchmarkHelper
    # Run benchmark-ips comparison (output suppressed by default)
    # @param time [Integer] Calculation time in seconds
    # @param warmup [Integer] Warmup time in seconds
    # @param quiet [Boolean] Suppress output
    # @yield [Benchmark::IPS::Job] Block receives job for adding reports
    # @return [Benchmark::IPS::Report] Benchmark report
    def compare_performance(time: 2, warmup: 1, quiet: true)
      report = nil

      Benchmark.ips(quiet: quiet) do |x|
        x.config(time: time, warmup: warmup)
        yield x
        x.compare! unless quiet
        report = x
      end

      report
    end

    # Simple timing for a block
    # @yield Block to time
    # @return [Float] Elapsed time in seconds
    def measure_time
      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      yield
      Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
    end

    # Measure memory delta during block execution
    # @yield Block to measure
    # @return [Integer] Memory delta in bytes
    def measure_memory
      GC.start
      before = get_memory_usage
      yield
      GC.start
      get_memory_usage - before
    end

    private

    def get_memory_usage
      ApiClient::SystemInfo.rss_kb * 1024
    end
  end
end

RSpec.configure do |config|
  config.include Support::BenchmarkHelper, :benchmark
end
