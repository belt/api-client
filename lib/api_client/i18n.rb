require "i18n"

module ApiClient
  # I18n integration for ApiClient
  #
  # Provides translated error messages with English defaults.
  # Locale files are loaded automatically in Rails via Railtie,
  # or on first use in standalone Ruby.
  #
  # @example Translate a message
  #   ApiClient::I18n.t("errors.circuit_open", service: "payments")
  #   # => "Circuit open for service: payments"
  #
  module I18n
    LOCALE_PATH = File.expand_path("../../config/locales/*.yml", __dir__).freeze

    # @api private
    @loaded = false
    @load_mutex = Mutex.new

    # Class instance variables below are intentional: mutex-guarded lazy locale loading.
    class << self
      # Translate a key under the api_client namespace
      #
      # @param key [String, Symbol] Translation key (relative to api_client.)
      # @param options [Hash] Interpolation variables
      # @return [String] Translated message
      def t(key, **options)
        ensure_loaded!
        ::I18n.t(key, scope: :api_client, **options)
      end

      # Load locale files into I18n backend
      # Safe to call multiple times (idempotent).
      # @return [void]
      def load!
        @load_mutex.synchronize do
          return if @loaded

          locale_files = Dir[LOCALE_PATH]
          # Only touch load_path when files are missing — the setter
          # deinitializes the backend, forcing a full reload of all locales.
          unless (locale_files - ::I18n.load_path).empty?
            ::I18n.load_path |= locale_files
          end
          @loaded = true
        end
      end

      # Reset loaded state (for testing)
      # @api private
      def reset!
        @load_mutex.synchronize { @loaded = false }
      end

      private

      def ensure_loaded!
        return if @loaded # standard:disable ThreadSafety/ClassInstanceVariable

        load!
      end
    end
  end
end
