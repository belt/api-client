module ApiClient
  module Jwt
    # Base error class for JWT operations
    class Error < ApiClient::Error; end

    # Raised when jwt gem is not available or version too old
    class JwtUnavailableError < Error
      def initialize(message = nil)
        super(message || I18n.t("jwt.unavailable"))
      end
    end

    # Raised when algorithm is forbidden or not allowed
    class InvalidAlgorithmError < Error
      attr_reader :algorithm

      def initialize(algorithm, message = nil)
        @algorithm = algorithm
        super(message || I18n.t("jwt.invalid_algorithm", algorithm: algorithm))
      end
    end

    # Raised when JWK structure is invalid
    class InvalidJwkError < Error; end

    # Raised when HMAC secret is too weak
    class WeakSecretError < Error; end

    # Raised when key not found in JWKS
    class KeyNotFoundError < Error
      attr_reader :kid, :jwks_uri

      def initialize(kid:, jwks_uri: nil)
        @kid = kid
        @jwks_uri = jwks_uri
        message = if jwks_uri
          I18n.t("jwt.key_not_found_at_uri", kid: kid, jwks_uri: jwks_uri)
        else
          I18n.t("jwt.key_not_found", kid: kid)
        end
        super(message)
      end
    end

    # Raised when JWKS fetch fails
    class JwksFetchError < Error
      attr_reader :uri, :status

      def initialize(uri:, status: nil, message: nil)
        @uri = uri
        @status = status
        super(message || I18n.t("jwt.jwks_fetch_failed", uri: uri, status: status))
      end
    end

    # Raised when token verification fails
    class TokenVerificationError < Error
      attr_reader :original_error

      def initialize(original_error = nil, message = nil)
        @original_error = original_error
        super(message || original_error&.message || I18n.t("jwt.token_verification_failed"))
      end
    end
  end
end
