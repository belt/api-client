require "spec_helper"

RSpec.describe "Profiling", :integration, :profile do
  describe "CPU profiling" do
    it "profiles batch request execution" do
      client = client_for_server
      requests = 20.times.map { |i| {method: :get, path: "/users/#{i + 1}"} }

      result = profile_cpu do
        5.times { client.batch(requests) }
      end

      expect(result[:samples]).to be > 0
    end
  end

  describe "memory profiling" do
    it "profiles memory allocations" do
      skip "memory_profiler not available" unless MEMORY_PROFILER_AVAILABLE

      client = client_for_server
      requests = 10.times.map { |i| {method: :get, path: "/users/#{i + 1}"} }

      report = profile_memory do
        3.times { client.batch(requests) }
      end

      expect(report.total_allocated).to be > 0
      expect(report.total_retained).to be < 50_000
    end
  end

  describe "allocation profiling" do
    it "profiles object allocations" do
      client = client_for_server
      requests = 5.times.map { |i| {method: :get, path: "/users/#{i + 1}"} }

      result = profile_allocations do
        client.batch(requests)
      end

      expect(result[:samples]).to be > 0
    end
  end

  describe "trace profiling" do
    it "generates call graph" do
      skip "ruby-prof not available" unless RUBY_PROF_AVAILABLE

      client = client_for_server

      result = profile_trace do
        client.get("/health")
      end

      path = save_call_graph(result, name: "single-request")
      expect(File.exist?(path)).to be true
    end
  end
end

RSpec.describe ApiClient::Profiling do
  let(:output_dir) { ApiClient::Profiling::DEFAULT_OUTPUT_DIR }

  after do
    ApiClient::Profiling.disable_auto_profiling!
    FileUtils.rm_rf(output_dir) if Dir.exist?(output_dir)
  end

  describe ".cpu" do
    it "profiles CPU usage and returns dump path" do
      path = ApiClient::Profiling.cpu { 1 + 1 }
      expect(path).to match(/stackprof-cpu-.*\.dump/)
      expect(File.exist?(path)).to be true
    end

    it "accepts custom interval" do
      path = ApiClient::Profiling.cpu(interval: 500) { sleep 0.001 }
      expect(File.exist?(path)).to be true
    end

    it "accepts custom output path" do
      custom_path = File.join(output_dir, "custom-cpu.dump")
      path = ApiClient::Profiling.cpu(out: custom_path) { 1 + 1 }
      expect(path).to eq(custom_path)
      expect(File.exist?(custom_path)).to be true
    end
  end

  describe ".wall" do
    it "profiles wall-clock time and returns dump path" do
      path = ApiClient::Profiling.wall { sleep 0.001 }
      expect(path).to match(/stackprof-wall-.*\.dump/)
      expect(File.exist?(path)).to be true
    end

    it "accepts custom output path" do
      custom_path = File.join(output_dir, "custom-wall.dump")
      path = ApiClient::Profiling.wall(out: custom_path) { sleep 0.001 }
      expect(path).to eq(custom_path)
    end
  end

  describe ".allocations" do
    it "profiles object allocations" do
      path = ApiClient::Profiling.allocations { Array.new(100) { {} } }
      expect(path).to match(/stackprof-object-.*\.dump/)
      expect(File.exist?(path)).to be true
    end

    it "accepts custom output path" do
      custom_path = File.join(output_dir, "custom-alloc.dump")
      path = ApiClient::Profiling.allocations(out: custom_path) { [] }
      expect(path).to eq(custom_path)
    end
  end

  describe ".run" do
    it "creates output directory if missing" do
      FileUtils.rm_rf(output_dir)
      ApiClient::Profiling.run { 1 }
      expect(Dir.exist?(output_dir)).to be true
    end

    it "uses default mode :cpu" do
      path = ApiClient::Profiling.run { 1 }
      expect(path).to include("cpu")
    end

    it "supports :wall mode" do
      path = ApiClient::Profiling.run(mode: :wall) { 1 }
      expect(path).to include("wall")
    end

    it "supports :object mode" do
      path = ApiClient::Profiling.run(mode: :object, interval: 1) { [] }
      expect(path).to include("object")
    end
  end

  describe ".flamegraph" do
    it "generates HTML flamegraph from dump" do
      # Need enough work to generate samples
      dump_path = ApiClient::Profiling.wall(interval: 100) do
        10_000.times { [1, 2, 3].map(&:to_s).join }
      end
      html_path = ApiClient::Profiling.flamegraph(dump_path)

      expect(html_path).to eq(dump_path.sub(".dump", ".html"))
      expect(File.exist?(html_path)).to be true
    end

    it "accepts custom output path" do
      dump_path = ApiClient::Profiling.wall(interval: 100) do
        10_000.times { [1, 2, 3].map(&:to_s) }
      end
      custom_html = File.join(output_dir, "custom-flame.html")
      result = ApiClient::Profiling.flamegraph(dump_path, output_path: custom_html)

      expect(result).to eq(custom_html)
      expect(File.exist?(custom_html)).to be true
    end
  end

  describe ".print_report" do
    # null STDOUT
    let(:output) { StringIO.new }

    it "loads and prints report from dump file" do
      dump_path = ApiClient::Profiling.wall(interval: 100) do
        10_000.times { [1, 2, 3].map(&:to_s) }
      end

      expect { ApiClient::Profiling.print_report(dump_path, output: output) }.not_to raise_error
      expect(output.string).to include("Mode:")
    end

    it "accepts limit parameter" do
      dump_path = ApiClient::Profiling.wall(interval: 100) do
        10_000.times { [1, 2, 3].map(&:to_s) }
      end

      expect { ApiClient::Profiling.print_report(dump_path, limit: 5, output: output) }
        .not_to raise_error
    end
  end

  describe ".profile_if_slow" do
    it "captures profile when block exceeds threshold" do
      events = []
      subscriber = ApiClient::Hooks.subscribe(:profile_captured) do |*args|
        event = ActiveSupport::Notifications::Event.new(*args)
        events << event.payload
      end

      ApiClient::Profiling.profile_if_slow(threshold_ms: 1) do
        sleep 0.01
        "result"
      end

      ApiClient::Hooks.unsubscribe(subscriber)
      expect(events.size).to eq(1)
      expect(events.first[:path]).to match(/stackprof.*\.dump/)
    end

    it "skips profile when block is fast" do
      events = []
      subscriber = ApiClient::Hooks.subscribe(:profile_captured) do |*args|
        events << args
      end

      ApiClient::Profiling.profile_if_slow(threshold_ms: 5000) do
        "fast"
      end

      ApiClient::Hooks.unsubscribe(subscriber)
      expect(events).to be_empty
    end

    it "returns block result" do
      result = ApiClient::Profiling.profile_if_slow(threshold_ms: 5000) { 42 }
      expect(result).to eq(42)
    end
  end

  describe ".auto_profile_slow_requests!" do
    it "configures auto-profiling" do
      ApiClient::Profiling.auto_profile_slow_requests!(threshold_ms: 500, sample_rate: 0.5)

      config = ApiClient::Profiling.auto_profile_config
      expect(config).to include(
        threshold_ms: 500,
        sample_rate: 0.5,
        enabled: true
      )
    end
  end

  describe ".disable_auto_profiling!" do
    it "clears configuration" do
      ApiClient::Profiling.auto_profile_slow_requests!(threshold_ms: 100)
      ApiClient::Profiling.disable_auto_profiling!

      expect(ApiClient::Profiling.auto_profile_config).to be_nil
    end
  end

  describe ".recent_profiles" do
    before do
      FileUtils.mkdir_p(output_dir)
      3.times do |i|
        File.write(File.join(output_dir, "stackprof-cpu-#{i}.dump"), "data")
        sleep 0.01
      end
    end

    it "lists recent profiles" do
      profiles = ApiClient::Profiling.recent_profiles(limit: 2)
      expect(profiles.size).to eq(2)
      expect(profiles.first[:path]).to include("stackprof-cpu-2")
    end

    it "includes metadata" do
      profile = ApiClient::Profiling.recent_profiles.first
      expect(profile).to include(:path, :size, :created_at, :mode)
    end
  end

  describe ".cleanup!" do
    before do
      FileUtils.mkdir_p(output_dir)
      5.times do |i|
        File.write(File.join(output_dir, "stackprof-cpu-#{i}.dump"), "data")
      end
    end

    it "keeps specified number of files" do
      deleted = ApiClient::Profiling.cleanup!(keep: 2)
      expect(deleted).to eq(3)
      expect(Dir.glob(File.join(output_dir, "*.dump")).size).to eq(2)
    end

    it "deletes files older than threshold" do
      FileUtils.rm_rf(output_dir)
      FileUtils.mkdir_p(output_dir)

      old_file = File.join(output_dir, "stackprof-cpu-old.dump")
      new_file = File.join(output_dir, "stackprof-cpu-new.dump")

      File.write(old_file, "old")
      File.utime(Time.now - 100, Time.now - 100, old_file)
      File.write(new_file, "new")

      ApiClient::Profiling.cleanup!(keep: 10, older_than: 50)

      expect(File.exist?(old_file)).to be false
      expect(File.exist?(new_file)).to be true
    end

    it "cleans up HTML files too" do
      File.write(File.join(output_dir, "stackprof-cpu-0.html"), "html")
      deleted = ApiClient::Profiling.cleanup!(keep: 0)
      expect(deleted).to be >= 6
    end
  end

  describe ".recent_profiles edge cases" do
    it "returns :unknown mode for non-standard filenames" do
      FileUtils.mkdir_p(output_dir)
      File.write(File.join(output_dir, "custom-profile.dump"), "data")

      profiles = ApiClient::Profiling.recent_profiles
      custom = profiles.find { |p| p[:path].include?("custom-profile") }
      expect(custom[:mode]).to eq(:unknown)
    end
  end

  describe "auto-profile subscriber" do
    it "instruments slow requests when threshold exceeded" do
      events = []
      subscriber = ApiClient::Hooks.subscribe(:request_slow) do |*args|
        event = ActiveSupport::Notifications::Event.new(*args)
        events << event.payload
      end

      ApiClient::Profiling.auto_profile_slow_requests!(threshold_ms: 1, sample_rate: 1.0)

      # instrument with a block measures duration automatically
      # duration is in ms, so sleeping 20ms should exceed 1ms threshold
      ActiveSupport::Notifications.instrument(
        "api_client.request.complete", method: :get, url: "/slow"
      ) do
        sleep 0.025
      end

      ApiClient::Hooks.unsubscribe(subscriber)

      expect(events.size).to eq(1)
      expect(events.first).to include(:duration_ms, :threshold_ms, :method, :url)
      expect(events.first[:method]).to eq(:get)
      expect(events.first[:url]).to eq("/slow")
    end

    it "respects sample_rate" do
      events = []
      subscriber = ApiClient::Hooks.subscribe(:request_slow) do |*args|
        events << args
      end

      # sample_rate: 0.0 means never sample
      ApiClient::Profiling.auto_profile_slow_requests!(threshold_ms: 1, sample_rate: 0.0)

      ActiveSupport::Notifications.instrument(
        "api_client.request.complete", method: :get, url: "/test"
      ) do
        sleep 0.02
      end

      ApiClient::Hooks.unsubscribe(subscriber)
      expect(events).to be_empty
    end

    it "skips when disabled" do
      events = []
      subscriber = ApiClient::Hooks.subscribe(:request_slow) do |*args|
        events << args
      end

      ApiClient::Profiling.auto_profile_slow_requests!(threshold_ms: 1)
      ApiClient::Profiling.disable_auto_profiling!

      ActiveSupport::Notifications.instrument(
        "api_client.request.complete", method: :get, url: "/test"
      ) do
        sleep 0.02
      end

      ApiClient::Hooks.unsubscribe(subscriber)
      expect(events).to be_empty
    end

    it "skips fast requests" do
      events = []
      subscriber = ApiClient::Hooks.subscribe(:request_slow) do |*args|
        events << args
      end

      ApiClient::Profiling.auto_profile_slow_requests!(threshold_ms: 5000, sample_rate: 1.0)

      ActiveSupport::Notifications.instrument(
        "api_client.request.complete", method: :get, url: "/fast"
      ) do
        # Fast - no sleep
      end

      ApiClient::Hooks.unsubscribe(subscriber)
      expect(events).to be_empty
    end
  end

  describe "Middleware" do
    let(:app) { ->(env) { [200, {}, ["OK"]] } }

    describe "when disabled" do
      it "passes through without profiling" do
        middleware = ApiClient::Profiling::Middleware.new(app, enabled: false)
        status, _headers, _body = middleware.call({"PATH_INFO" => "/test"})

        expect(status).to eq(200)
        expect(Dir.glob(File.join(output_dir, "*.dump"))).to be_empty
      end
    end

    describe "with path filter" do
      it "profiles matching paths" do
        middleware = ApiClient::Profiling::Middleware.new(
          app,
          enabled: true,
          path: "/api"
        )

        env = {"PATH_INFO" => "/api/users"}
        middleware.call(env)

        expect(env["api_client.profile_path"]).to match(/stackprof.*\.dump/)
      end

      it "skips non-matching paths" do
        middleware = ApiClient::Profiling::Middleware.new(
          app,
          enabled: true,
          path: "/api"
        )

        env = {"PATH_INFO" => "/health"}
        middleware.call(env)

        expect(env["api_client.profile_path"]).to be_nil
      end
    end

    describe "standard profiling mode" do
      it "profiles all requests when enabled without path filter" do
        middleware = ApiClient::Profiling::Middleware.new(
          app,
          enabled: true,
          mode: :wall,
          interval: 500
        )

        env = {"PATH_INFO" => "/anything"}
        middleware.call(env)

        expect(env["api_client.profile_path"]).to match(/stackprof-wall.*\.dump/)
      end
    end

    describe "auto_slow mode" do
      it "only profiles slow requests" do
        middleware = ApiClient::Profiling::Middleware.new(
          app,
          enabled: true,
          auto_slow: true,
          slow_threshold_ms: 5000
        )

        middleware.call({"PATH_INFO" => "/fast"})
        expect(Dir.glob(File.join(output_dir, "*.dump"))).to be_empty
      end

      it "captures profile for slow requests" do
        slow_app = ->(_env) { sleep 0.02; [200, {}, ["OK"]] }
        middleware = ApiClient::Profiling::Middleware.new(
          slow_app,
          enabled: true,
          auto_slow: true,
          slow_threshold_ms: 1
        )

        events = []
        subscriber = ApiClient::Hooks.subscribe(:profile_captured) do |*args|
          event = ActiveSupport::Notifications::Event.new(*args)
          events << event.payload
        end

        middleware.call({"PATH_INFO" => "/slow"})

        ApiClient::Hooks.unsubscribe(subscriber)
        expect(events.size).to eq(1)
      end
    end
  end
end
