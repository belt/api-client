require_relative "errors"

begin
  require "jwt"
rescue LoadError => _err
  # Git-sourced gems e.g. jwt for ruby-4, need Bundler to wire load paths
  begin
    require "bundler/setup"
    require "jwt"
  rescue LoadError, Bundler::GemNotFound => _jwt_err # rubocop:disable Lint/SuppressedException
  end
end

module ApiClient
  module Jwt
    # Security auditor for JWT operations
    #
    # Validates gem availability, algorithm security, JWK structure,
    # and secret strength. Enforces best practices from RFC 8725.
    #
    # @example Check availability
    #   ApiClient::Jwt::Auditor.available?  # => true/false
    #
    # @example Validate algorithm
    #   ApiClient::Jwt::Auditor.validate_algorithm!("RS256")  # => true
    #   ApiClient::Jwt::Auditor.validate_algorithm!("none")   # raises InvalidAlgorithmError
    #
    module Auditor
      # Minimum jwt gem version with security fixes
      MINIMUM_JWT_VERSION = "2.7"
      MINIMUM_JWT_GEM_VERSION = Gem::Version.new(MINIMUM_JWT_VERSION).freeze

      # Asymmetric algorithms (recommended for API-to-API)
      ALLOWED_ALGORITHMS = %w[
        RS256 RS384 RS512
        ES256 ES384 ES512
        PS256 PS384 PS512
      ].freeze

      # Precomputed set for O(1) lookup
      ALLOWED_ALGORITHMS_SET = ALLOWED_ALGORITHMS.to_set.freeze

      # Forbidden algorithms (security risks)
      # - none: No signature verification
      # - HS*: Symmetric, prone to algorithm confusion attacks
      FORBIDDEN_ALGORITHMS = %w[none HS256 HS384 HS512].freeze
      FORBIDDEN_ALGORITHMS_SET = FORBIDDEN_ALGORITHMS.to_set.freeze

      # Minimum secret length for HMAC (if explicitly allowed)
      MINIMUM_SECRET_BYTES = 32

      # JWK validation rules keyed by algorithm prefix pattern
      JWK_VALIDATORS = {
        /^(?:RS|PS)/ => {required: %w[kty n e], expected_kty: "RSA", label: "RSA"},
        /^ES/ => {required: %w[kty crv x y], expected_kty: "EC", label: "EC"},
        /^HS/ => {required: %w[kty k], expected_kty: "oct", label: "Symmetric"}
      }.freeze

      # standard:disable ThreadSafety/ClassInstanceVariable
      class << self
        # Check if jwt gem is available and meets minimum version
        # Memoized since gem availability doesn't change at runtime
        # @return [Boolean]
        def available?
          return @available if defined?(@available)

          @available = check_jwt_availability
        end

        # Require jwt gem, raising if unavailable
        # @raise [JwtUnavailableError] if gem not available
        def require_jwt!
          return true if @jwt_loaded

          raise JwtUnavailableError unless available?

          require "jwt"
          @jwt_loaded = true
        end

        # Reset memoized state (for testing)
        # @api private
        def reset!
          remove_instance_variable(:@available) if instance_variable_defined?(:@available)
          remove_instance_variable(:@jwt_loaded) if instance_variable_defined?(:@jwt_loaded)
        end

        private

        def check_jwt_availability
          version_string = if defined?(::JWT::VERSION::STRING)
            ::JWT::VERSION::STRING
          else
            Gem.loaded_specs["jwt"]&.version&.to_s
          end
          return false unless version_string

          Gem::Version.new(version_string) >= MINIMUM_JWT_GEM_VERSION
        end

        public

        # Validate algorithm against security policy
        # @param algorithm [String, Symbol] Algorithm name
        # @param allow_hmac [Boolean] Override to allow HMAC (not recommended)
        # @raise [InvalidAlgorithmError] if algorithm forbidden or unknown
        # @return [true]
        def validate_algorithm!(algorithm, allow_hmac: false)
          alg = algorithm.to_s.upcase

          if alg == "NONE"
            raise InvalidAlgorithmError.new(
              algorithm,
              I18n.t("jwt.none_forbidden")
            )
          end

          if !allow_hmac && FORBIDDEN_ALGORITHMS_SET.include?(alg)
            raise InvalidAlgorithmError.new(
              algorithm,
              I18n.t("jwt.hmac_discouraged")
            )
          end

          unless algorithm_allowed?(algorithm, allow_hmac: allow_hmac)
            raise InvalidAlgorithmError.new(
              algorithm,
              I18n.t("jwt.algorithm_not_allowed", algorithm: alg, allowed: ALLOWED_ALGORITHMS.join(", "))
            )
          end

          true
        end

        # Check if algorithm is allowed (non-raising)
        # @param algorithm [String, Symbol] Algorithm name
        # @return [Boolean]
        def algorithm_allowed?(algorithm, allow_hmac: false)
          alg = algorithm.to_s.upcase
          return false if alg == "NONE"
          return false if !allow_hmac && FORBIDDEN_ALGORITHMS_SET.include?(alg)

          ALLOWED_ALGORITHMS_SET.include?(alg) || (allow_hmac && alg.start_with?("HS"))
        end

        # Validate JWK has required fields for algorithm
        # @param jwk [Hash, JWT::JWK] JWK to validate
        # @param algorithm [String, Symbol] Expected algorithm
        # @raise [InvalidJwkError] if JWK invalid
        # @return [true]
        def validate_jwk!(jwk, algorithm)
          jwk_hash = normalize_jwk(jwk)
          alg = algorithm.to_s.upcase

          validator = JWK_VALIDATORS.find { |pattern, _| alg.match?(pattern) }&.last
          raise InvalidJwkError, I18n.t("jwt.unknown_algorithm_type", algorithm: alg) unless validator

          validate_jwk_fields!(jwk_hash, **validator)
        end

        # Validate HMAC secret strength
        # @param secret [String] Secret key
        # @raise [WeakSecretError] if secret too short
        # @return [true]
        def validate_secret_strength!(secret)
          if secret.nil? || secret.bytesize < MINIMUM_SECRET_BYTES
            raise WeakSecretError,
              I18n.t("jwt.weak_secret", minimum: MINIMUM_SECRET_BYTES, actual: secret&.bytesize || 0)
          end

          true
        end

        # Compute RFC 7638 JWK thumbprint
        # @param jwk [Hash, JWT::JWK] JWK to compute thumbprint for
        # @return [String] Base64url-encoded thumbprint
        def thumbprint(jwk)
          require_jwt!
          jwk_obj = jwk.is_a?(::JWT::JWK::KeyBase) ? jwk : ::JWT::JWK.new(jwk)
          ::JWT::JWK::Thumbprint.new(jwk_obj).generate
        end

        # List all allowed algorithms
        # @param include_hmac [Boolean] Include HMAC algorithms
        # @return [Array<String>]
        def allowed_algorithms(include_hmac: false)
          if include_hmac
            ALLOWED_ALGORITHMS + %w[HS256 HS384 HS512]
          else
            ALLOWED_ALGORITHMS.dup
          end
        end

        private

        def normalize_jwk(jwk)
          if jwk.is_a?(::JWT::JWK::KeyBase) || jwk.respond_to?(:export)
            jwk.export
          elsif jwk.keys.first.is_a?(Symbol)
            jwk.transform_keys(&:to_s)
          else
            jwk
          end
        end

        def validate_jwk_fields!(jwk, required:, expected_kty:, label:)
          missing = required - jwk.keys.map(&:to_s)

          if missing.any?
            raise InvalidJwkError, I18n.t("jwt.jwk_missing_fields", label: label, fields: missing.join(", "))
          end

          kty = jwk["kty"]
          unless kty == expected_kty
            raise InvalidJwkError, I18n.t("jwt.jwk_kty_mismatch", label: label, expected: expected_kty, actual: kty)
          end

          true
        end
      end
      # standard:enable ThreadSafety/ClassInstanceVariable
    end
  end
end
