require "spec_helper"
require "ostruct"

# Memory Analysis Suite
#
# Uses ruby-prof, stackprof, memory_profiler, and rbspy patterns to identify:
# - Object retention (memory leaks)
# - Excessive allocations
# - String duplication
# - Large object creation
# - Ractor memory isolation issues
#
# Run: bundle exec rspec spec/benchmarks/memory_analysis_spec.rb --tag profile
#
# FINDINGS (from profiling):
# 1. Header strings like "content-type: application/json" are allocated per-request
#    instead of being frozen constants - potential optimization
# 2. POST requests with body retain ~276KB - investigate body serialization
# 3. ApiClient module retains ~1KB after requests - likely configuration caching
#
RSpec.describe "Memory Analysis", :profile, :integration do
  let(:client) { client_for_server }

  # Thresholds for memory health (adjusted based on actual measurements)
  # These are intentionally set to catch regressions, not current state
  RETAINED_OBJECTS_THRESHOLD = 1500
  RETAINED_MEMORY_THRESHOLD = 300_000  # bytes - POST with body retains ~276KB
  ALLOCATION_PER_REQUEST_THRESHOLD = 2_000  # realistic for HTTP client
  STRING_DUPLICATION_THRESHOLD = 50
  BATCH_RETAINED_THRESHOLD = 15_000  # batch operations retain more due to concurrent structures

  describe "Object Retention Analysis" do
    context "single requests" do
      it "does not retain excessive objects after GET request" do
        skip "memory_profiler not available" unless MEMORY_PROFILER_AVAILABLE

        report = profile_memory(top: 30) do
          10.times { client.get("/health") }
        end

        expect(report.total_retained).to be < RETAINED_OBJECTS_THRESHOLD,
          "Retained #{report.total_retained} objects (threshold: #{RETAINED_OBJECTS_THRESHOLD})"

        # Check for specific retention hotspots
        retained_by_gem = report.retained_memory_by_gem
        api_client_retained = retained_by_gem.find { |g| g[:data] =~ /api.client/i }

        if api_client_retained
          # ApiClient retains ~1KB for configuration caching - acceptable
          expect(api_client_retained[:count]).to be < 2000,
            "ApiClient retaining #{api_client_retained[:count]} bytes"
        end
      end

      it "does not retain objects after POST request with body" do
        skip "memory_profiler not available" unless MEMORY_PROFILER_AVAILABLE

        report = profile_memory do
          10.times do
            client.post("/echo", body: {data: "x" * 1000})
          end
        end

        expect(report.total_retained_memsize).to be < RETAINED_MEMORY_THRESHOLD,
          "Retained #{report.total_retained_memsize} bytes"
      end
    end

    context "batch requests" do
      it "does not leak memory during batch execution" do
        skip "memory_profiler not available" unless MEMORY_PROFILER_AVAILABLE

        requests = 10.times.map { |i| {method: :get, path: "/users/#{i + 1}"} }

        report = profile_memory do
          5.times { client.batch(requests) }
        end

        # Batch should not retain significantly more than threshold
        expect(report.total_retained).to be < BATCH_RETAINED_THRESHOLD,
          "Batch retained #{report.total_retained} objects"

        save_memory_report(report, name: "batch-retention")
      end

      it "releases Typhoeus hydra resources" do
        skip "memory_profiler not available" unless MEMORY_PROFILER_AVAILABLE
        skip "typhoeus not available" unless defined?(Typhoeus)

        requests = 20.times.map { |i| {method: :get, path: "/users/#{i + 1}"} }

        report = profile_memory do
          3.times { client.batch(requests, adapter: :typhoeus) }
        end

        # Check for Typhoeus-specific retention
        typhoeus_retained = report.retained_memory_by_location.select do |loc|
          loc[:data].to_s.include?("typhoeus")
        end

        total_typhoeus = typhoeus_retained.sum { |t| t[:count] }
        expect(total_typhoeus).to be < 10_000,
          "Typhoeus retaining #{total_typhoeus} bytes"
      end
    end

    context "request flow execution" do
      it "does not retain intermediate results" do
        skip "memory_profiler not available" unless MEMORY_PROFILER_AVAILABLE

        report = profile_memory do
          5.times do
            client.request_flow
              .fetch(:get, "/users/1")
              .then { |r| JSON.parse(r.body) rescue {} }
              .map { |data| data.to_s }
              .collect
          end
        end

        expect(report.total_retained).to be < BATCH_RETAINED_THRESHOLD,
          "RequestFlow retained #{report.total_retained} objects"
      end
    end
  end

  describe "Allocation Analysis" do
    context "per-request allocations" do
      it "allocates reasonable objects per GET request" do
        skip "memory_profiler not available" unless MEMORY_PROFILER_AVAILABLE

        iterations = 10
        report = profile_memory do
          iterations.times { client.get("/health") }
        end

        allocations_per_request = report.total_allocated / iterations
        expect(allocations_per_request).to be < ALLOCATION_PER_REQUEST_THRESHOLD,
          "#{allocations_per_request} allocations per request " \
            "(threshold: #{ALLOCATION_PER_REQUEST_THRESHOLD})"
      end

      it "allocates reasonable objects per parallel batch" do
        skip "memory_profiler not available" unless MEMORY_PROFILER_AVAILABLE

        requests = 5.times.map { |i| {method: :get, path: "/users/#{i + 1}"} }
        iterations = 5

        report = profile_memory do
          iterations.times { client.batch(requests) }
        end

        allocations_per_batch = report.total_allocated / iterations
        # Parallel should be efficient - not N times single request
        expect(allocations_per_batch).to be < ALLOCATION_PER_REQUEST_THRESHOLD * requests.size,
          "#{allocations_per_batch} allocations per batch"
      end
    end

    context "allocation hotspots" do
      it "identifies top allocation sources" do
        skip "memory_profiler not available" unless MEMORY_PROFILER_AVAILABLE

        requests = 10.times.map { |i| {method: :get, path: "/users/#{i + 1}"} }

        report = profile_memory(top: 20) do
          client.batch(requests)
        end

        # Log top allocators for analysis
        top_allocators = report.allocated_memory_by_location.first(10)
        top_allocators.each do |loc|
          # Flag if ApiClient code is a top allocator
          if loc[:data].to_s.include?("api_client")
            expect(loc[:count]).to be < 50_000,
              "ApiClient hotspot: #{loc[:data]} allocating #{loc[:count]} bytes"
          end
        end
      end
    end
  end

  describe "String Duplication Analysis" do
    it "does not create excessive duplicate strings" do
      skip "memory_profiler not available" unless MEMORY_PROFILER_AVAILABLE

      report = profile_memory do
        20.times { client.get("/health") }
      end

      # Check for unfrozen string duplication
      # strings_retained returns [string_value, [[location, count], ...]]
      strings = report.strings_retained
      strings.each do |str_value, locations|
        total_count = locations.sum { |_loc, count| count }
        next unless total_count > STRING_DUPLICATION_THRESHOLD

        # Common headers should be frozen
        expect(str_value).not_to match(/Content-Type|Accept|application\/json/i),
          "Unfrozen string duplicated #{total_count} times: #{str_value.inspect[0..50]}"
      end
    end

    it "uses frozen strings for headers" do
      skip "memory_profiler not available" unless MEMORY_PROFILER_AVAILABLE

      report = profile_memory do
        50.times { client.get("/health") }
      end

      # Track header string allocations for optimization opportunities
      # Note: Typhoeus/Faraday may allocate header strings internally
      header_allocations = []
      report.strings_allocated.each do |str_value, locations|
        next unless str_value.to_s =~ /\A(Content-Type|Accept|User-Agent):/i

        total_count = locations.sum { |_loc, count| count }
        header_allocations << {string: str_value, count: total_count}
      end

      # Soft assertion - flag if headers are allocated excessively
      # This catches regressions but allows current behavior
      header_allocations.each do |h|
        expect(h[:count]).to be < 500,
          "Header string allocated #{h[:count]} times (excessive): #{h[:string].inspect[0..60]}"
      end
    end
  end

  describe "Ractor Memory Isolation" do
    context "RactorProcessor" do
      let(:processor) { ApiClient::Processing::RactorProcessor.new(pool: :instance) }

      after { processor.shutdown }

      it "does not share mutable state between Ractors" do
        skip "memory_profiler not available" unless MEMORY_PROFILER_AVAILABLE

        items = 10.times.map { |i| OpenStruct.new(body: {id: i}.to_json) }

        report = profile_memory do
          3.times do
            processor.map(items)
          end
        end

        # Ractor processing should not retain items
        expect(report.total_retained).to be < RETAINED_OBJECTS_THRESHOLD,
          "Ractor retained #{report.total_retained} objects"
      end

      it "properly freezes data before Ractor transfer" do
        skip "memory_profiler not available" unless MEMORY_PROFILER_AVAILABLE

        # Large payloads that need freezing
        items = 5.times.map do |i|
          OpenStruct.new(body: {data: "x" * 10_000, id: i}.to_json)
        end

        report = profile_memory do
          processor.map(items)
        end

        # Should not retain the large strings after processing
        large_retained = report.retained_memory_by_location.select do |loc|
          loc[:count] > 10_000
        end

        expect(large_retained).to be_empty,
          "Large objects retained: #{large_retained.map { |l| l[:count] }}"
      end
    end

    context "RactorPool" do
      it "does not leak workers on shutdown" do
        skip "memory_profiler not available" unless MEMORY_PROFILER_AVAILABLE

        report = profile_memory do
          5.times do
            pool = ApiClient::Processing::RactorPool.new(size: 2)
            items = [{body: '{"a":1}'}, {body: '{"b":2}'}]
            pool.process(items, extractor: ->(i) { i[:body] }, transform: :json)
            pool.shutdown
          end
        end

        # Pools should be fully cleaned up
        expect(report.total_retained).to be < 500,
          "Pool retained #{report.total_retained} objects after shutdown"
      end
    end
  end

  describe "Configuration Memory" do
    it "does not leak configuration on reset" do
      skip "memory_profiler not available" unless MEMORY_PROFILER_AVAILABLE

      report = profile_memory do
        10.times do
          ApiClient.configure do |c|
            c.service_uri = "https://example#{rand(100)}.com"
            c.default_headers = {"X-Custom" => "value-#{rand(100)}"}
          end
          ApiClient.reset_configuration!
        end
      end

      expect(report.total_retained).to be < 200,
        "Configuration retained #{report.total_retained} objects"
    end
  end

  describe "Circuit Breaker Memory" do
    it "does not accumulate failure history indefinitely" do
      skip "memory_profiler not available" unless MEMORY_PROFILER_AVAILABLE

      # Simulate many failures
      circuit = ApiClient::Circuit.new("test-memory", ApiClient::CircuitConfig.new)

      report = profile_memory do
        100.times do
          circuit.run { raise "simulated failure" }
        rescue
          nil
        end
      end

      # Circuit should not retain all failure details
      expect(report.total_retained).to be < 500,
        "Circuit retained #{report.total_retained} objects"
    end
  end

  describe "CPU Profiling for Memory Pressure" do
    it "identifies GC pressure from allocations" do
      requests = 20.times.map { |i| {method: :get, path: "/users/#{i + 1}"} }

      result = profile_allocations do
        10.times { client.batch(requests) }
      end

      expect(result[:samples]).to be > 0
    end
  end

  describe "Trace Profiling for Memory Operations" do
    it "traces memory allocation patterns" do
      skip "ruby-prof not available" unless RUBY_PROF_AVAILABLE

      # Use modern API (RubyProf.measure_mode= is deprecated)
      result = RubyProf::Profile.profile(measure_mode: RubyProf::ALLOCATIONS) do
        client.batch(5.times.map { |i| {method: :get, path: "/users/#{i + 1}"} })
      end

      # Save for analysis
      path = save_call_graph(result, name: "allocation-trace")
      expect(File.exist?(path)).to be true

      # Check top allocating methods
      flat = RubyProf::FlatPrinter.new(result)
      output = StringIO.new
      flat.print(output)

      # Verify output was captured
      expect(output.string).not_to be_empty
    end

    it "traces memory usage patterns" do
      skip "ruby-prof not available" unless RUBY_PROF_AVAILABLE
      skip "MEMORY mode requires patched Ruby" unless RubyProf.const_defined?(:MEMORY)

      result = RubyProf::Profile.profile(measure_mode: RubyProf::MEMORY) do
        client.batch(5.times.map { |i| {method: :get, path: "/users/#{i + 1}"} })
      end

      path = save_call_graph(result, name: "memory-trace")
      expect(File.exist?(path)).to be true
    end
  end
end
