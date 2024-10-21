require "spec_helper"
require "api_client"
require "api_client/profiling"
require "fileutils"

# Profiling specs are inherently multi-step: profile, then verify output.
# rubocop:disable RSpec/ExampleLength, RSpec/MultipleExpectations
RSpec.describe ApiClient::Profiling do
  let(:output_dir) { ApiClient::Profiling::DEFAULT_OUTPUT_DIR }
  let(:profiling) { ApiClient::Profiling } # rubocop:disable RSpec/DescribedClass

  before do
    FileUtils.rm_rf(output_dir)
    profiling.disable_auto_profiling!
  end

  after do
    FileUtils.rm_rf(output_dir)
    profiling.disable_auto_profiling!
  end

  describe ".cpu" do
    it "profiles CPU usage and returns dump path" do
      path = described_class.cpu { 1 + 1 }
      expect(path).to match(/stackprof-cpu-.*\.dump$/)
      expect(File.exist?(path)).to be true
    end

    it "accepts custom output path" do
      custom_path = File.join(output_dir, "custom-cpu.dump")
      path = described_class.cpu(out: custom_path) { 1 + 1 }
      expect(path).to eq(custom_path)
      expect(File.exist?(custom_path)).to be true
    end
  end

  describe ".wall" do
    it "profiles wall-clock time and returns dump path" do
      path = described_class.wall { sleep(0.001) }
      expect(path).to match(/stackprof-wall-.*\.dump$/)
      expect(File.exist?(path)).to be true
    end
  end

  describe ".allocations" do
    it "profiles object allocations and returns dump path" do
      path = described_class.allocations { Array.new(100) }
      expect(path).to match(/stackprof-object-.*\.dump$/)
      expect(File.exist?(path)).to be true
    end
  end

  describe ".run" do
    it "creates output directory if needed" do
      FileUtils.rm_rf(output_dir)
      described_class.run(mode: :cpu) { 1 + 1 }
      expect(Dir.exist?(output_dir)).to be true
    end
  end

  describe ".profile_if_slow" do
    it "returns block result" do
      result = described_class.profile_if_slow(threshold_ms: 1000) { 42 }
      expect(result).to eq(42)
    end

    it "keeps profile for slow operations" do
      path = nil
      subscriber = ApiClient::Hooks.subscribe(:profile_captured) do |*args|
        event = ActiveSupport::Notifications::Event.new(*args)
        path = event.payload[:path]
      end

      described_class.profile_if_slow(threshold_ms: 1) { sleep(0.01) }

      expect(path).not_to be_nil
      expect(File.exist?(path)).to be true
    ensure
      ApiClient::Hooks.unsubscribe(subscriber)
    end

    it "deletes profile for fast operations" do
      described_class.profile_if_slow(threshold_ms: 10_000) { 1 + 1 }

      slow_profiles = Dir.glob(File.join(output_dir, "*slow*.dump"))
      expect(slow_profiles).to be_empty
    end
  end

  describe ".auto_profile_slow_requests!" do
    it "enables profiling" do
      described_class.auto_profile_slow_requests!(threshold_ms: 500, mode: :cpu, sample_rate: 0.5)
      expect(described_class.auto_profile_config[:enabled]).to be true
    end

    it "stores threshold_ms" do
      described_class.auto_profile_slow_requests!(threshold_ms: 500, mode: :cpu, sample_rate: 0.5)
      expect(described_class.auto_profile_config[:threshold_ms]).to eq(500)
    end

    it "stores mode" do
      described_class.auto_profile_slow_requests!(threshold_ms: 500, mode: :cpu, sample_rate: 0.5)
      expect(described_class.auto_profile_config[:mode]).to eq(:cpu)
    end

    it "stores sample_rate" do
      described_class.auto_profile_slow_requests!(threshold_ms: 500, mode: :cpu, sample_rate: 0.5)
      expect(described_class.auto_profile_config[:sample_rate]).to eq(0.5)
    end
  end

  describe ".disable_auto_profiling!" do
    it "clears configuration" do
      described_class.auto_profile_slow_requests!(threshold_ms: 500)
      described_class.disable_auto_profiling!
      expect(described_class.auto_profile_config).to be_nil
    end
  end

  describe ".flamegraph" do
    it "generates HTML from dump file with samples" do
      dump_path = described_class.wall { 10_000.times { [1, 2, 3].map(&:to_s) } }
      custom_html = File.join(output_dir, "custom.html")
      html_path = described_class.flamegraph(dump_path, output_path: custom_html)

      expect(html_path).to eq(custom_html)
      expect(File.exist?(custom_html)).to be true
    end
  end

  describe ".recent_profiles" do
    it "returns profile info with expected keys" do
      described_class.cpu { 1 + 1 }

      profiles = described_class.recent_profiles(limit: 10)
      expect(profiles.size).to be >= 1
      expect(profiles.first).to include(:path, :size, :created_at, :mode)
    end

    it "respects limit" do
      3.times do |i|
        described_class.run(mode: :cpu, out: File.join(output_dir, "test-#{i}.dump")) { 1 + 1 }
      end

      profiles = described_class.recent_profiles(limit: 2)
      expect(profiles.size).to eq(2)
    end
  end

  describe ".cleanup!" do
    it "keeps recent files based on keep parameter" do
      5.times do |i|
        described_class.run(mode: :cpu, out: File.join(output_dir, "cleanup-#{i}.dump")) { 1 + 1 }
      end

      initial_count = Dir.glob(File.join(output_dir, "*.dump")).size
      expect(initial_count).to eq(5)

      deleted = described_class.cleanup!(keep: 3)
      expect(deleted).to eq(2)
      expect(Dir.glob(File.join(output_dir, "*.dump")).size).to eq(3)
    end

    it "deletes files older than specified seconds" do
      3.times do |i|
        described_class.run(mode: :cpu, out: File.join(output_dir, "old-#{i}.dump")) { 1 + 1 }
      end

      old_file = File.join(output_dir, "old-0.dump")
      FileUtils.touch(old_file, mtime: Time.now - 3600)

      deleted = described_class.cleanup!(keep: 10, older_than: 1800)
      expect(deleted).to be >= 1
    end
  end

  describe ".print_report" do
    it "prints text report from dump file" do
      dump_path = described_class.cpu { 1000.times { [1, 2, 3].map(&:to_s) } }
      output = StringIO.new

      expect { described_class.print_report(dump_path, limit: 5, output: output) }
        .not_to raise_error
      expect(output.string).not_to be_empty
    end
  end

  describe "auto-profiling slow request handling" do
    it "stores and clears subscriber on enable/disable" do
      described_class.auto_profile_slow_requests!(threshold_ms: 500, sample_rate: 1.0)
      expect(described_class.auto_profile_config[:enabled]).to be true

      described_class.disable_auto_profiling!
      expect(described_class.auto_profile_config).to be_nil
    end

    it "fires request_slow when duration exceeds threshold" do
      events = []
      subscriber = ApiClient::Hooks.subscribe(:request_slow) do |*args|
        events << ActiveSupport::Notifications::Event.new(*args)
      end

      described_class.auto_profile_slow_requests!(threshold_ms: 10, sample_rate: 1.0)

      mock_event = instance_double(ActiveSupport::Notifications::Event,
        duration: 50.0,
        payload: {method: :get, url: "/slow", status: 200})

      described_class.send(:handle_slow_request, mock_event,
        {threshold_ms: 10, mode: :wall, sample_rate: 1.0, enabled: true})

      expect(events.size).to eq(1)
      expect(events.first.payload[:duration_ms]).to eq(50)
    ensure
      ApiClient::Hooks.unsubscribe(subscriber)
      described_class.disable_auto_profiling!
    end

    it "does not fire when duration is below threshold" do
      events = []
      subscriber = ApiClient::Hooks.subscribe(:request_slow) do |*args|
        events << ActiveSupport::Notifications::Event.new(*args)
      end

      described_class.auto_profile_slow_requests!(threshold_ms: 1000, sample_rate: 1.0)

      mock_event = instance_double(ActiveSupport::Notifications::Event,
        duration: 5.0,
        payload: {method: :get, url: "/fast", status: 200})

      described_class.send(:handle_slow_request, mock_event,
        {threshold_ms: 1000, mode: :wall, sample_rate: 1.0, enabled: true})

      expect(events).to be_empty
    ensure
      ApiClient::Hooks.unsubscribe(subscriber)
      described_class.disable_auto_profiling!
    end
  end

  describe ApiClient::Profiling::Middleware do
    let(:app) { ->(env) { [200, {}, ["OK"]] } }

    context "when disabled" do
      subject(:middleware) { described_class.new(app, enabled: false) }

      it "passes through without profiling" do
        env = {"PATH_INFO" => "/api/test"}
        status, _headers, _body = middleware.call(env)

        expect(status).to eq(200)
        expect(env["api_client.profile_path"]).to be_nil
      end
    end

    context "when enabled" do
      subject(:middleware) { described_class.new(app, enabled: true, mode: :cpu) }

      it "profiles request and sets profile path" do
        env = {"PATH_INFO" => "/api/test"}
        status, _headers, _body = middleware.call(env)

        expect(status).to eq(200)
        expect(env["api_client.profile_path"]).to match(/stackprof-cpu/)
      end
    end

    context "with path filter" do
      subject(:middleware) { described_class.new(app, enabled: true, path: "/api") }

      it "profiles matching paths" do
        env = {"PATH_INFO" => "/api/test"}
        middleware.call(env)
        expect(env["api_client.profile_path"]).not_to be_nil
      end

      it "skips non-matching paths" do
        env = {"PATH_INFO" => "/other/path"}
        middleware.call(env)
        expect(env["api_client.profile_path"]).to be_nil
      end
    end

    context "with auto_slow mode" do
      subject(:middleware) {
        described_class.new(
          app, enabled: true, auto_slow: true, slow_threshold_ms: 10_000
        )
      }

      it "profiles and cleans up fast requests" do
        env = {"PATH_INFO" => "/api/test"}
        status, _headers, _body = middleware.call(env)

        expect(status).to eq(200)
        slow_profiles = Dir.glob(File.join(output_dir, "*slow*.dump"))
        expect(slow_profiles).to be_empty
      end
    end
  end
end
# rubocop:enable RSpec/ExampleLength, RSpec/MultipleExpectations
