# frozen_string_literal: true

module ApiClient
  # JIT activation helper — application-level concern, not library-level.
  #
  # Eagerly loads gems with native extensions BEFORE enabling JIT to avoid
  # potential deadlocks where native extension initialization contends with
  # JIT compilation.
  #
  # Strategy:
  #   Ruby 3.1+ → YJIT (stable, production-ready)
  #   Ruby <3.1  → no JIT
  #
  # @example In spec_helper.rb or application boot
  #   require "api_client"
  #   # ... other requires ...
  #   ApiClient::JIT.activate
  #
  # @example Checking status
  #   ApiClient::JIT.active?       # => true
  #   ApiClient::JIT.active_name   # => :yjit
  #
  module JIT
    # Runtime gems with native extensions that may be present in production.
    # These ship as optional runtime deps (concurrency adapters, auth, profiling).
    # Native extensions must initialize outside JIT compilation.
    RUNTIME_GEMS = %w[
      concurrent async async/http/internet typhoeus
      jwt
      strscan stackprof
      connection_pool
    ].freeze

    # Dev/test gems with native extensions.
    # Only loaded outside production environments.
    DEV_GEMS = %w[
      debug
      fiddle
    ].freeze

    class << self
      # Load native-extension gems then enable the appropriate JIT.
      # Safe to call multiple times — no-ops if JIT already active.
      #
      # @param include_dev [Boolean] load dev/test gems too (default: true)
      def activate(include_dev: true)
        load_gems(RUNTIME_GEMS)
        load_gems(DEV_GEMS) if include_dev
        enable_jit
      end

      # @return [Boolean] true if YJIT is currently enabled
      def active?
        yjit_enabled?
      end

      # @return [Symbol, nil] :yjit or nil
      def active_name
        return :yjit if yjit_enabled?

        nil
      end

      private

      # Eagerly require gems so their native extensions initialize
      # outside JIT compilation. LoadError is expected for absent gems.
      def load_gems(list)
        list.each do |gem_name|
          require gem_name
        rescue LoadError
          # Not in bundle — skip
        end
      end

      def enable_jit
        enable_yjit if RUBY_VERSION >= "3.1"
      end

      # YJIT — production JIT for Ruby 3.1+
      def enable_yjit
        return unless defined?(RubyVM::YJIT) && RubyVM::YJIT.respond_to?(:enable)

        RubyVM::YJIT.enable unless RubyVM::YJIT.enabled?
      end

      def yjit_enabled?
        defined?(RubyVM::YJIT) && RubyVM::YJIT.respond_to?(:enabled?) && RubyVM::YJIT.enabled?
      end
    end
  end
end
