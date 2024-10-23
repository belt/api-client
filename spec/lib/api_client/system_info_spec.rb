require "spec_helper"
require "api_client"

RSpec.describe ApiClient::SystemInfo do
  # Reset cached reader between examples so build_* branches
  # can be exercised independently via stubbing.
  before do
    described_class.instance_variable_set(:@rss_reader, nil)
  end

  describe ".rss_kb" do
    it "returns an integer" do
      expect(described_class.rss_kb).to be_a(Integer)
    end

    it "returns a positive value" do
      expect(described_class.rss_kb).to be > 0
    end

    it "returns a plausible value (> 1 MB for a Ruby process)" do
      expect(described_class.rss_kb).to be > 1024
    end

    it "caches the reader after first call" do
      described_class.rss_kb
      reader = described_class.instance_variable_get(:@rss_reader)
      described_class.rss_kb
      expect(described_class.instance_variable_get(:@rss_reader)).to be(reader)
    end

    it "reflects memory growth after allocation" do
      before_rss = described_class.rss_kb
      big = Array.new(10_000) { "x" * 1024 }
      after_rss = described_class.rss_kb
      expect(after_rss).to be >= before_rss
      big.clear
    end
  end

  describe "platform-specific readers" do
    context "when running on macOS (darwin)" do
      before do
        skip "darwin-only test" unless RUBY_PLATFORM.include?("darwin")
      end

      it "uses Fiddle-based Mach task_info reader" do
        reader = described_class.send(:build_darwin_reader)
        expect(reader).to respond_to(:call)
      end

      it "returns a positive integer from darwin reader" do
        reader = described_class.send(:build_darwin_reader)
        rss = reader.call
        expect(rss).to be > 0
      end

      it "returns non-zero from task_info with invalid port" do # rubocop:disable RSpec/ExampleLength
        libc = Fiddle::Handle::DEFAULT
        task_info_fn = Fiddle::Function.new(
          libc["task_info"],
          [Fiddle::TYPE_INT, Fiddle::TYPE_INT,
            Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP],
          Fiddle::TYPE_INT
        )
        buf = "\0" * 48
        count = [12].pack("I")
        kr = task_info_fn.call(0, 20, buf, count)
        expect(kr).not_to eq(0)
      end
    end

    context "when running on Linux" do
      before do
        skip "linux-only test" unless File.readable?("/proc/self/status")
      end

      it "parses VmRSS as a positive integer" do
        reader = described_class.send(:build_linux_reader)
        rss = reader.call
        expect(rss).to be > 0
      end
    end

    context "with fallback reader" do
      it "returns an integer from ps" do
        reader = described_class.send(:build_fallback_reader)
        expect(reader.call).to be_a(Integer)
      end

      it "returns a non-negative value" do
        reader = described_class.send(:build_fallback_reader)
        expect(reader.call).to be >= 0
      end
    end
  end

  describe "reader selection" do
    it "selects darwin reader on macOS" do
      skip "darwin-only test" unless RUBY_PLATFORM.include?("darwin")
      described_class.rss_kb
      reader = described_class.instance_variable_get(:@rss_reader)
      expect(reader).to be_lambda
    end
  end
end
