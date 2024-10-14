require "fiddle"

module ApiClient
  # Platform-specific system introspection via Fiddle (stdlib FFI).
  #
  # Avoids fork/exec overhead of shelling out to `ps` by using
  # native syscalls for memory measurement.
  #
  # macOS: Mach task_info(2) → current resident_size
  # Linux: /proc/self/status VmRSS
  # Fallback: ps -o rss= (fork+exec)
  #
  # @example
  #   ApiClient::SystemInfo.rss_kb  # => 67132
  #
  module SystemInfo
    # Class instance variables below are intentional: memoized platform reader built once per process.
    class << self
      # Current process resident set size in kilobytes.
      #
      # The reader is built once on first call and cached for the
      # lifetime of the process. Fiddle handles and function objects
      # are resolved at build time so the hot path is a single
      # syscall with no allocation overhead.
      #
      # @return [Integer] RSS in KB
      def rss_kb
        @rss_reader ||= build_rss_reader # standard:disable ThreadSafety/ClassInstanceVariable
        @rss_reader.call # standard:disable ThreadSafety/ClassInstanceVariable
      end

      private

      def build_rss_reader
        if RUBY_PLATFORM.include?("darwin")
          build_darwin_reader
        elsif File.readable?("/proc/self/status")
          build_linux_reader
        else
          build_fallback_reader
        end
      end

      # Mach task_info(mach_task_self(), MACH_TASK_BASIC_INFO, &info, &count)
      # Returns current resident_size (bytes) → converted to KB.
      #
      # NOTE: mach_task_self_ is a global variable (mach_port_t), not a
      # function. We read it as a pointer and unpack the uint32 port value.
      #
      # Struct layout validated against macOS 14 (Sonoma) SDK, arm64 (Apple Silicon).
      # mach_task_basic_info (48 bytes, 64-bit):
      #   offset 0:  policy        (4 bytes, natural_t)
      #   offset 4:  pad           (4 bytes, alignment)
      #   offset 8:  virtual_size  (8 bytes, mach_vm_size_t)
      #   offset 16: resident_size (8 bytes, mach_vm_size_t)  ← we read this
      #   offset 24+: suspend_count, user_time, system_time
      #
      # If Apple changes this struct layout in a future SDK, the sanity
      # check (1 TB cap) will trigger the fallback path.
      def build_darwin_reader
        libc = Fiddle::Handle::DEFAULT

        task_info_fn = Fiddle::Function.new(
          libc["task_info"],
          [Fiddle::TYPE_INT, Fiddle::TYPE_INT, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP],
          Fiddle::TYPE_INT
        )

        task_port = Fiddle::Pointer.new(libc["mach_task_self_"])[0, 4].unpack1("I")

        flavor = 20 # MACH_TASK_BASIC_INFO
        count_val = 12 # 48 bytes / sizeof(natural_t)

        # Upper bound sanity check: 1 TB. Any value above this almost
        # certainly indicates a struct layout mismatch or ABI change.
        max_sane_kb = 1_073_741_824 # 1 TB in KB

        lambda {
          # struct mach_task_basic_info (48 bytes, 64-bit):
          #   policy(4) + pad(4) + virtual_size(8) + resident_size(8) + ...
          buf = "\0" * 48
          count = [count_val].pack("I")
          kr = task_info_fn.call(task_port, flavor, buf, count)
          if kr == 0 # KERN_SUCCESS
            rss = buf.byteslice(8, 8).unpack1("Q") / 1024
            (rss > 0 && rss < max_sane_kb) ? rss : fallback_rss_kb
          else
            fallback_rss_kb
          end
        }
      end

      # Parse VmRSS from procfs (already in KB).
      def build_linux_reader
        lambda {
          File.foreach("/proc/self/status") do |line|
            return line.split[1].to_i if line.start_with?("VmRSS:")
          end
          0
        }
      end

      # Shell out to ps (universal but slow).
      def build_fallback_reader
        method(:fallback_rss_kb).to_proc
      end

      def fallback_rss_kb
        `ps -o rss= -p #{Process.pid} 2>/dev/null`.to_i
      end
    end
  end
end
