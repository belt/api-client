require "json"
require "uri"

module ApiClient
  # URI validation policy for SSRF and path traversal prevention
  #
  # Validates resolved URIs before requests are dispatched across ALL
  # execution paths (sequential, batch, fan-out). This is a cross-cutting
  # concern that works regardless of which backend adapter is in use.
  #
  # @example Configuration
  #   ApiClient.configure do |config|
  #     config.allowed_hosts = ["api.example.com", "*.internal.example.com"]
  #     config.blocked_hosts = ["metadata.google.internal"]
  #     config.blocked_schemes = %w[file ftp data javascript]
  #   end
  #
  # @example Direct validation
  #   UriPolicy.validate!("https://api.example.com/users", config)
  #
  module UriPolicy
    @blocked_hosts_mutex = Mutex.new
    @default_blocked_hosts = nil

    class << self # standard:disable ThreadSafety/ClassInstanceVariable -- mutex-guarded lazy SSRF blocklist
      # Thread-safe lazy loader for the default SSRF blocked-host list.
      # Parsed once from config/ssrf_hosts.jsonc on first access, then
      # cached for the lifetime of the process.
      #
      # Lazy (instead of require-time constant) to avoid a strscan
      # thread-safety crash when multiple Falcon workers autoload this
      # module concurrently.  The Mutex guarantees only one thread
      # executes JSON.parse.
      #
      # @see config/ssrf_hosts.jsonc
      # @return [Array<String>] frozen list of blocked hostnames
      def default_blocked_hosts
        # Fast path: already populated (no lock needed, reading a frozen ref).
        return @default_blocked_hosts if @default_blocked_hosts # standard:disable ThreadSafety/ClassInstanceVariable

        @blocked_hosts_mutex.synchronize do # standard:disable ThreadSafety/ClassInstanceVariable
          @default_blocked_hosts ||= begin
            jsonc_path = ApiClient.root.join("config", "ssrf_hosts.jsonc").to_s
            raw = File.read(jsonc_path)
            json = raw.gsub(%r{//[^\n]*}, "").gsub(%r{/\*.*?\*/}m, "")
            JSON.parse(json).freeze
          end
        end
      end

      # Validate a URI string against the policy
      #
      # @param uri_string [String, URI] URI to validate
      # @param config [Configuration] ApiClient configuration
      # @raise [SsrfBlockedError] if URI violates policy
      # @return [void]
      def validate!(uri_string, config)
        return unless config.uri_policy_enabled

        uri = parse(uri_string)
        check_scheme!(uri, config)
        check_path_traversal!(uri, config)
        check_blocked_host!(uri, config)
        check_allowed_hosts!(uri, config)
        check_blocked_ip!(uri, config)
      end

      private

      # @raise [SsrfBlockedError]
      def parse(uri_string)
        uri = uri_string.is_a?(URI::Generic) ? uri_string : URI.parse(uri_string.to_s)
        raise SsrfBlockedError.new(uri_string, I18n.t("uri_policy.unparseable")) unless uri.host
        uri
      rescue URI::InvalidURIError
        raise SsrfBlockedError.new(uri_string, I18n.t("uri_policy.malformed"))
      end

      def check_scheme!(uri, config)
        scheme = uri.scheme&.downcase
        return unless config.blocked_schemes.include?(scheme)

        raise SsrfBlockedError.new(uri, I18n.t("uri_policy.blocked_scheme", scheme: scheme))
      end

      def check_path_traversal!(uri, config)
        path = uri.path
        return if path.nil? || path.empty?

        # Decode percent-encoded traversal attempts (%2e%2e%2f)
        decoded = URI.decode_www_form_component(path)
        return unless config.path_traversal_pattern.match?(decoded)

        raise SsrfBlockedError.new(uri, I18n.t("uri_policy.path_traversal"))
      end

      def check_blocked_host!(uri, config)
        host = uri.host.downcase

        # Check both lists without allocating a merged array per request.
        matched = config.blocked_hosts.any? { |pattern| host_match?(host, pattern) } ||
          default_blocked_hosts.any? { |pattern| host_match?(host, pattern) }

        return unless matched

        raise SsrfBlockedError.new(uri, I18n.t("uri_policy.blocked_host", host: host))
      end

      def check_allowed_hosts!(uri, config)
        allowed = config.allowed_hosts
        return if allowed.empty?

        host = uri.host.downcase
        return if allowed.any? { |pattern| host_match?(host, pattern) }

        raise SsrfBlockedError.new(uri, I18n.t("uri_policy.host_not_allowed", host: host))
      end

      def check_blocked_ip!(uri, config)
        host = uri.host
        ip = parse_ip(host)
        return unless ip

        # Skip IP check when host matches the configured service_uri.
        # The user explicitly chose this host — SSRF risk is from
        # path manipulation reaching *different* hosts, not the
        # configured one.
        configured_host = begin
          URI.parse(config.service_uri).host
        rescue
          nil
        end
        return if configured_host && host == configured_host

        blocked = config.blocked_networks.find { |net| net.include?(ip) }
        return unless blocked

        raise SsrfBlockedError.new(uri, I18n.t("uri_policy.blocked_network", network: blocked))
      end

      # Fast regex pre-check: only attempt IPAddr.new when the host
      # looks like an IP (starts with digit or contains colon for IPv6).
      # Avoids exception overhead for the common hostname case.
      IP_CANDIDATE = /\A[\d:]/

      def parse_ip(host)
        return nil unless IP_CANDIDATE.match?(host)

        IPAddr.new(host)
      rescue IPAddr::InvalidAddressError
        nil
      end

      # Match host against pattern (supports wildcard prefix)
      # "*.example.com" matches "api.example.com" and "deep.api.example.com"
      # "example.com" matches only "example.com"
      def host_match?(host, pattern)
        pattern = pattern.downcase
        if pattern.start_with?("*.")
          suffix = pattern[1..] # ".example.com"
          host.end_with?(suffix) || host == pattern[2..]
        else
          host == pattern
        end
      end
    end
  end
end
