require "json"
require_relative "auditor"
require_relative "errors"

module ApiClient
  module Jwt
    # JWKS endpoint client with caching and automatic refresh
    #
    # Implements best practices for JWKS retrieval:
    # - TTL-based caching (default: 10 minutes)
    # - Rate-limited refresh on kid_not_found
    # - Graceful degradation on fetch failure
    # - Filtering by use=sig and allowed algorithms
    #
    # @example Basic usage
    #   client = ApiClient::Jwt::JwksClient.new(
    #     jwks_uri: "https://auth.example.com/.well-known/jwks.json"
    #   )
    #   key = client.key(kid: "key-123")
    #
    # @example With JWT.decode
    #   JWT.decode(token, nil, true, {
    #     algorithms: ["RS256"],
    #     jwks: client.to_loader
    #   })
    #
    class JwksClient
      # Default cache TTL (10 minutes)
      DEFAULT_TTL = 600

      # Minimum time between kid_not_found refreshes (5 minutes)
      REFRESH_GRACE_PERIOD = 300

      attr_reader :jwks_uri, :ttl

      # @return [Set<String>, nil] Allowed algorithms as a frozen Set for O(1) lookup
      def allowed_algorithms
        @allowed_algorithms&.to_a
      end

      # @param jwks_uri [String] JWKS endpoint URL
      # @param http_client [ApiClient::Base, nil] HTTP client (auto-created if nil)
      # @param ttl [Integer] Cache TTL in seconds
      # @param allowed_algorithms [Array<String>, nil] Filter keys by algorithm
      # @param logger [Logger, nil] Logger for debug output
      def initialize(
        jwks_uri:, http_client: nil, ttl: DEFAULT_TTL,
        allowed_algorithms: nil, logger: nil
      )
        Auditor.require_jwt!

        @jwks_uri = jwks_uri.freeze
        @http_client = http_client
        @ttl = ttl
        @allowed_algorithms = allowed_algorithms&.map { |alg| alg.to_s.upcase }&.to_set&.freeze
        @logger = logger || default_logger
        @parsed_uri = nil
        @uri_path = nil
        @base_uri = nil

        parse_uri(jwks_uri)
        reset_cache_state
      end

      # Get key by kid
      # @param kid [String] Key ID
      # @param algorithm [String, nil] Expected algorithm (for validation)
      # @return [JWT::JWK]
      # @raise [KeyNotFoundError] if key not found after refresh
      def key(kid:, algorithm: nil)
        now = current_time

        cached = lookup_cached(kid)
        if cached && !stale_at?(now)
          validate_algorithm!(cached, algorithm) if algorithm
          return cached
        end

        refresh_if_needed!(now)
        found = lookup_cached(kid)

        raise KeyNotFoundError.new(kid: kid, jwks_uri: @jwks_uri) unless found

        validate_algorithm!(found, algorithm) if algorithm
        found
      end

      # Get key, returning nil if not found
      # @param kid [String] Key ID
      # @return [JWT::JWK, nil]
      def key_or_nil(kid:)
        key(kid: kid)
      rescue KeyNotFoundError
        nil
      end

      # Force cache refresh
      # @param force [Boolean] Bypass rate limiting
      def refresh!(force: false)
        refresh_if_needed!(current_time, force: force)
      end

      # Create loader proc for JWT.decode
      # @return [Proc]
      def to_loader
        lambda do |options|
          if options[:kid_not_found]
            last_refresh = @mutex.synchronize { @last_refresh }
            now = current_time
            if now - last_refresh > REFRESH_GRACE_PERIOD
              @logger.debug { "kid_not_found refresh triggered" }
              refresh_if_needed!(now, force: true)
            end
          end

          jwks_set
        end
      end

      # Get all cached keys as JWT::JWK::Set
      # @return [JWT::JWK::Set]
      def jwks_set
        now = current_time
        refresh_if_needed!(now) if stale_at?(now) || cache_empty?

        ::JWT::JWK::Set.new(@mutex.synchronize { @cache.values })
      end

      # List cached key IDs
      # @return [Array<String>]
      def cached_kids
        @mutex.synchronize { @cache.keys.dup }
      end

      # Check if cache is stale
      # @return [Boolean]
      def stale?
        current_time - @last_refresh > @ttl
      end

      # Clear cache
      def clear!
        @mutex.synchronize do
          @cache.clear
          @last_refresh = current_time - @ttl - 1
          @last_refresh_wall = 0
        end
      end

      private

      def lookup_cached(kid)
        @mutex.synchronize { @cache[kid] }
      end

      def parse_uri(jwks_uri)
        @parsed_uri = URI.parse(jwks_uri)
        @uri_path = @parsed_uri.path.freeze
        @base_uri = build_base_uri.freeze
      end

      def reset_cache_state
        @cache = {}
        @last_refresh = current_time - @ttl - 1
        @mutex = Mutex.new
      end

      def stale_at?(now)
        now - @last_refresh > @ttl
      end

      def cache_empty?
        @cache.empty?
      end

      def needs_refresh?(now, force)
        force || stale_at?(now) || cache_empty?
      end

      def validate_algorithm!(found, algorithm)
        found_alg = found[:alg]
        return unless found_alg
        return if found_alg == algorithm.to_s.upcase

        @logger.warn { "JWK algorithm mismatch: expected #{algorithm}, got #{found_alg}" }
      end

      def current_time
        Process.clock_gettime(Process::CLOCK_MONOTONIC).to_i
      end

      def refresh_if_needed!(now, force: false)
        return unless needs_refresh?(now, force)

        @mutex.synchronize do
          # Double-check after acquiring lock
          return unless needs_refresh?(now, force)

          fetch_and_cache_keys
          @last_refresh = now
        end
      rescue => error
        @logger.error { "JWKS fetch failed: #{error.message}" }
        raise if cache_empty?
      end

      def fetch_and_cache_keys
        response = http_client.get(@uri_path)

        unless response.success?
          raise JwksFetchError.new(uri: @jwks_uri, status: response.status)
        end

        jwks_hash = JSON.parse(response.body, symbolize_names: true)
        process_jwks(jwks_hash)
      rescue Faraday::Error => error
        raise JwksFetchError.new(uri: @jwks_uri, message: error.message)
      end

      def process_jwks(jwks_hash)
        keys_array = jwks_hash[:keys] || []
        new_cache = {}

        keys_array.each do |jwk_hash|
          next unless eligible_key?(jwk_hash)

          jwk = ::JWT::JWK.new(jwk_hash)
          kid = jwk[:kid]
          next unless kid

          new_cache[kid] = jwk
        end

        # Atomic swap - replaces old cache entirely
        @cache = new_cache

        @logger.debug { "JWKS refreshed: #{new_cache.size} keys cached" }
      end

      def eligible_key?(jwk_hash)
        # Skip non-signing keys
        use = jwk_hash[:use]
        return false if use && use != "sig"

        # Skip keys with disallowed algorithms
        alg = jwk_hash[:alg]
        if @allowed_algorithms && alg
          return false unless @allowed_algorithms.include?(alg.to_s.upcase)
        end

        true
      end

      def http_client
        @http_client ||= build_default_client
      end

      def build_default_client
        ApiClient.new(
          service_uri: @base_uri,
          retry: {max: 2},
          circuit: {threshold: 3, cool_off: 60}
        )
      end

      def build_base_uri
        base = "#{@parsed_uri.scheme}://#{@parsed_uri.host}"
        port = @parsed_uri.port
        base += ":#{port}" if port && ![80, 443].include?(port)
        base
      end

      def default_logger
        if defined?(::Rails) && ::Rails.respond_to?(:logger) && ::Rails.logger
          ::Rails.logger
        else
          Logger.new(File::NULL)
        end
      end
    end
  end
end
