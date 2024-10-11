require "stackprof"

module ApiClient
  # Production-safe profiling utilities
  #
  # Uses stackprof (sampling profiler) for low-overhead CPU analysis.
  # Safe to use in production with minimal performance impact.
  #
  # @example Profile a block of requests
  #   ApiClient::Profiling.cpu do
  #     client.batch(requests)
  #   end
  #   # => writes to tmp/stackprof-{timestamp}.dump
  #
  # @example Generate flamegraph
  #   ApiClient::Profiling.flamegraph("tmp/stackprof.dump")
  #   # => tmp/stackprof.html
  #
  # @example Auto-profile slow requests
  #   ApiClient::Profiling.auto_profile_slow_requests!(threshold_ms: 500)
  #
  # @example Middleware usage (Rack)
  #   use ApiClient::Profiling::Middleware, enabled: true
  #
  module Profiling
    DEFAULT_OUTPUT_DIR = "tmp/profiles"
    DEFAULT_INTERVAL = 1000 # microseconds
    DEFAULT_SLOW_THRESHOLD_MS = 3000

    @profiling_mutex = Mutex.new

    class << self
      # Generate profiling methods for each mode
      # @!method cpu(interval:, out:, &block)
      #   Profile CPU usage (sampling)
      #   @param interval [Integer] Sampling interval in microseconds
      #   @param out [String, nil] Output file path
      #   @yield Block to profile
      #   @return [String] Path to dump file
      #
      # @!method wall(interval:, out:, &block)
      #   Profile wall-clock time (includes I/O)
      #   @param interval [Integer] Sampling interval in microseconds
      #   @param out [String, nil] Output file path
      #   @yield Block to profile
      #   @return [String] Path to dump file
      %i[cpu wall].each do |mode|
        define_method(mode) do |interval: DEFAULT_INTERVAL, out: nil, &block|
          run(mode: mode, interval: interval, out: out, &block)
        end
      end

      # Profile object allocations
      # @param out [String, nil] Output file path
      # @yield Block to profile
      # @return [String] Path to dump file
      def allocations(out: nil, &block)
        run(mode: :object, interval: 1, out: out, &block)
      end

      # Run stackprof with given options
      # @param mode [:cpu, :wall, :object] Profiling mode
      # @param interval [Integer] Sampling interval
      # @param out [String, nil] Output file path
      # @yield Block to profile
      # @return [String] Path to dump file
      def run(mode: :cpu, interval: DEFAULT_INTERVAL, out: nil, &block)
        ensure_output_dir
        out ||= default_output_path(mode)

        StackProf.run(mode: mode, interval: interval, out: out, raw: true, &block)
        out
      end

      # Profile with timing and auto-capture if slow
      # @param threshold_ms [Integer] Threshold in milliseconds
      # @param mode [:cpu, :wall] Profiling mode
      # @yield Block to profile
      # @return [Object] Block result
      def profile_if_slow(threshold_ms: DEFAULT_SLOW_THRESHOLD_MS, mode: :wall, &block)
        ensure_output_dir
        out = default_output_path("slow-#{mode}")
        result = nil
        duration_ms = nil

        StackProf.run(mode: mode, interval: DEFAULT_INTERVAL, out: out, raw: true) do
          start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          result = yield
          duration_ms = (
            (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000
          ).round
        end

        handle_slow_profile(out, duration_ms, threshold_ms, mode)
        result
      end

      # Enable auto-profiling of slow requests via hooks
      # @param threshold_ms [Integer] Threshold in milliseconds
      # @param mode [:cpu, :wall] Profiling mode
      # @param sample_rate [Float] Fraction of requests to profile (0.0-1.0)
      # standard:disable ThreadSafety/ClassInstanceVariable
      def auto_profile_slow_requests!(
        threshold_ms: DEFAULT_SLOW_THRESHOLD_MS,
        mode: :wall, sample_rate: 1.0
      )
        @profiling_mutex.synchronize do
          @slow_request_config = {
            threshold_ms: threshold_ms,
            mode: mode,
            sample_rate: sample_rate,
            enabled: true
          }.freeze

          # Subscribe to request events if not already subscribed
          setup_auto_profile_subscriber unless @auto_profile_subscriber
        end
      end

      # Disable auto-profiling
      def disable_auto_profiling!
        @profiling_mutex.synchronize do
          @slow_request_config = nil
          if @auto_profile_subscriber
            Hooks.unsubscribe(@auto_profile_subscriber)
            @auto_profile_subscriber = nil
          end
        end
      end

      # Current auto-profile configuration
      # @return [Hash, nil]
      def auto_profile_config
        @profiling_mutex.synchronize { @slow_request_config }
      end
      # standard:enable ThreadSafety/ClassInstanceVariable

      # Generate flamegraph HTML from dump file
      # @param dump_path [String] Path to stackprof dump
      # @param output_path [String, nil] Output HTML path
      # @return [String] Path to generated HTML
      def flamegraph(dump_path, output_path: nil)
        output_path ||= dump_path.sub(/\.dump$/, ".html")

        File.open(output_path, "w") do |file|
          load_report(dump_path).print_d3_flamegraph(file)
        end

        output_path
      end

      # Print text report from dump file
      # @param dump_path [String] Path to stackprof dump
      # @param limit [Integer] Number of frames to show
      # @param output [IO] Output stream (defaults to $stdout)
      def print_report(dump_path, limit: 20, output: $stdout)
        load_report(dump_path).print_text(false, limit, nil, nil, nil, nil, output)
      end

      # List recent profile dumps
      # @param limit [Integer] Max files to return
      # @return [Array<Hash>] Profile file info
      def recent_profiles(limit: 10)
        ensure_output_dir
        Dir.glob(File.join(DEFAULT_OUTPUT_DIR, "*.dump"))
          .sort_by { |file| File.mtime(file) }
          .reverse
          .first(limit)
          .map do |path|
            {
              path: path,
              size: File.size(path),
              created_at: File.mtime(path),
              mode: extract_mode_from_path(path)
            }
          end
      end

      # Clean up old profile files
      # @param keep [Integer] Number of recent files to keep
      # @param older_than [Integer, nil] Delete files older than N seconds
      def cleanup!(keep: 20, older_than: nil)
        ensure_output_dir
        files = Dir.glob(File.join(DEFAULT_OUTPUT_DIR, "*.{dump,html}"))
          .sort_by { |file| File.mtime(file) }
          .reverse

        to_delete = expired_files(files, keep, older_than)
        to_delete.each { |file| File.delete(file) if File.exist?(file) }
        to_delete.size
      end

      private

      # standard:disable ThreadSafety/ClassInstanceVariable
      def setup_auto_profile_subscriber
        @auto_profile_subscriber = Hooks.subscribe(:request_complete) do |*args|
          config = @profiling_mutex.synchronize { @slow_request_config }
          next unless config&.dig(:enabled)
          next if rand > config[:sample_rate]

          handle_slow_request(ActiveSupport::Notifications::Event.new(*args), config)
        end
      end
      # standard:enable ThreadSafety/ClassInstanceVariable

      def handle_slow_request(event, config)
        duration_ms = event.duration
        threshold = config[:threshold_ms]

        return unless duration_ms && duration_ms >= threshold

        payload = event.payload
        Hooks.instrument(:request_slow,
          duration_ms: duration_ms.round,
          threshold_ms: threshold,
          method: payload[:method],
          url: payload[:url])
      end

      def handle_slow_profile(out, duration_ms, threshold_ms, mode)
        if duration_ms >= threshold_ms
          Hooks.instrument(:request_slow,
            duration_ms: duration_ms,
            threshold_ms: threshold_ms)
          Hooks.instrument(:profile_captured,
            path: out, duration_ms: duration_ms, mode: mode)
        elsif File.exist?(out)
          File.delete(out)
        end
      end

      def load_report(dump_path)
        StackProf::Report.new(Marshal.load(File.binread(dump_path)))
      end

      def expired_files(files, keep, older_than)
        to_delete = files.drop(keep)

        if older_than
          cutoff = Time.now - older_than
          to_delete += files.select { |file| File.mtime(file) < cutoff }
        end

        to_delete.uniq
      end

      def ensure_output_dir
        FileUtils.mkdir_p(DEFAULT_OUTPUT_DIR)
      end

      def default_output_path(mode)
        timestamp = Time.now.strftime("%Y%m%d-%H%M%S")
        File.join(DEFAULT_OUTPUT_DIR, "stackprof-#{mode}-#{timestamp}.dump")
      end

      def extract_mode_from_path(path)
        if path =~ /stackprof-(\w+)-/
          $1.to_sym
        else
          :unknown
        end
      end
    end

    # Rack middleware for request profiling
    #
    # @example Basic usage
    #   use ApiClient::Profiling::Middleware,
    #       enabled: ENV['PROFILE'] == 'true',
    #       mode: :cpu,
    #       path: '/api'
    #
    # @example Auto-profile slow requests only
    #   use ApiClient::Profiling::Middleware,
    #       enabled: true,
    #       auto_slow: true,
    #       slow_threshold_ms: 500
    #
    class Middleware
      # All instance variables are set once in #initialize and never mutated,
      # making this middleware safe to share across Puma threads.
      def initialize(app, enabled: false, mode: :cpu, interval: 1000, path: nil,
        auto_slow: false, slow_threshold_ms: 1000)
        @app = app
        @enabled = enabled.freeze
        @mode = mode.freeze
        @interval = interval.freeze
        @path_filter = path.freeze
        @auto_slow = auto_slow.freeze
        @slow_threshold_ms = slow_threshold_ms.freeze
      end

      def call(env)
        return @app.call(env) unless profile_request?(env)

        if @auto_slow
          call_with_slow_detection(env)
        else
          call_with_profiling(env)
        end
      end

      private

      def call_with_profiling(env)
        response = nil
        output = Profiling.run(mode: @mode, interval: @interval) do
          response = @app.call(env)
        end

        env["api_client.profile_path"] = output
        response
      end

      def call_with_slow_detection(env)
        Profiling.profile_if_slow(
          threshold_ms: @slow_threshold_ms,
          mode: @mode
        ) do
          @app.call(env)
        end
      end

      def profile_request?(env)
        return false unless @enabled
        return true if @path_filter.nil?

        env["PATH_INFO"]&.start_with?(@path_filter)
      end
    end
  end
end
