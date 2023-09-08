# Profiling tools configuration for development and testing
#
# Tools available:
# - stackprof: Sampling profiler (production-safe, flamegraphs)
# - ruby-prof: Tracing profiler (dev only, detailed call graphs)
# - memory_profiler: Allocation analysis (dev only)
#
# Usage in specs:
#   it "profiles request handling", :profile do
#     profile_cpu { client.get("/users") }
#   end
#
#   it "checks memory", :profile do
#     report = profile_memory { client.batch(requests) }
#     expect(report.total_retained).to be < 1000
#   end

require "stackprof"

# Optional profilers (dev only, high overhead)
begin
  require "ruby-prof"
  RUBY_PROF_AVAILABLE = true
rescue LoadError
  RUBY_PROF_AVAILABLE = false
end

begin
  require "memory_profiler"
  MEMORY_PROFILER_AVAILABLE = true
rescue LoadError
  MEMORY_PROFILER_AVAILABLE = false
end

module Support
  module ProfilingHelper
    PROFILE_OUTPUT_DIR = ApiClient.root.join("tmp/profiles").to_s

    # CPU profiling with stackprof (sampling, low overhead)
    # @param mode [:cpu, :wall, :object] Profiling mode
    # @param interval [Integer] Sampling interval in microseconds
    # @param out [String, nil] Output file path
    # @yield Block to profile
    # @return [Hash] StackProf results
    def profile_cpu(mode: :cpu, interval: 1000, out: nil, &block)
      FileUtils.mkdir_p(PROFILE_OUTPUT_DIR)
      out ||= File.join(PROFILE_OUTPUT_DIR, "stackprof-#{Time.now.to_i}.dump")

      StackProf.run(mode: mode, interval: interval, out: out, raw: true, &block)
      Marshal.load(File.binread(out))
    end

    # Wall-clock profiling (includes I/O wait time)
    # @yield Block to profile
    # @return [Hash] StackProf results
    def profile_wall(&block)
      profile_cpu(mode: :wall, &block)
    end

    # Object allocation profiling
    # @yield Block to profile
    # @return [Hash] StackProf results
    def profile_allocations(&block)
      profile_cpu(mode: :object, interval: 1, &block)
    end

    # Memory profiling with memory_profiler (detailed allocations)
    # @param top [Integer] Number of top results to include
    # @yield Block to profile
    # @return [MemoryProfiler::Results]
    def profile_memory(top: 50, &block)
      skip "memory_profiler not available" unless MEMORY_PROFILER_AVAILABLE

      MemoryProfiler.report(top: top, &block)
    end

    # Detailed tracing with ruby-prof (call graphs)
    # @param measure_mode [Symbol] :wall, :cpu, :allocations, :memory
    # @yield Block to profile
    # @return [RubyProf::Profile]
    def profile_trace(measure_mode: :wall, &block)
      skip "ruby-prof not available" unless RUBY_PROF_AVAILABLE

      mode = case measure_mode
      when :wall then RubyProf::WALL_TIME
      when :cpu then RubyProf::PROCESS_TIME
      when :allocations then RubyProf::ALLOCATIONS
      when :memory then RubyProf::MEMORY
      else RubyProf::WALL_TIME
      end

      RubyProf::Profile.profile(measure_mode: mode, &block)
    end

    # Save ruby-prof result as HTML call graph
    # @param result [RubyProf::Result] Profile result
    # @param name [String] Output filename (without extension)
    def save_call_graph(result, name: "profile")
      skip "ruby-prof not available" unless RUBY_PROF_AVAILABLE

      FileUtils.mkdir_p(PROFILE_OUTPUT_DIR)
      path = File.join(PROFILE_OUTPUT_DIR, "#{name}-#{Time.now.to_i}.html")

      File.open(path, "w") do |file|
        RubyProf::GraphHtmlPrinter.new(result).print(file)
      end

      path
    end

    # Save memory report to file
    # @param report [MemoryProfiler::Results] Memory report
    # @param name [String] Output filename
    def save_memory_report(report, name: "memory")
      FileUtils.mkdir_p(PROFILE_OUTPUT_DIR)
      path = File.join(PROFILE_OUTPUT_DIR, "#{name}-#{Time.now.to_i}.txt")

      report.pretty_print(to_file: path)
      path
    end

    # Generate flamegraph command hint
    # @param dump_path [String] Path to stackprof dump
    # @return [String] Command to generate flamegraph
    def flamegraph_command(dump_path)
      "stackprof #{dump_path} --d3-flamegraph > #{dump_path.sub(".dump", ".html")}"
    end
  end
end

RSpec.configure do |config|
  config.include Support::ProfilingHelper, :profile

  # Clean up old profile files before suite
  config.before(:suite) do
    profile_dir = Support::ProfilingHelper::PROFILE_OUTPUT_DIR
    FileUtils.rm_rf(profile_dir) if Dir.exist?(profile_dir)
  end
end
