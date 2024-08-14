require "securerandom"
require_relative "auditor"
require_relative "errors"

module ApiClient
  module Jwt
    # JWT token encoder/decoder with security best practices enforced
    #
    # Implements RFC 8725 recommendations:
    # - Strict algorithm enforcement (never trust header)
    # - Mandatory expiration claims
    # - Issuer/audience validation
    #
    # @example Encode a token
    #   key = OpenSSL::PKey::RSA.generate(2048)
    #   token = ApiClient::Jwt::Token.new(algorithm: "RS256", key: key)
    #   jwt = token.encode({ sub: "user123" }, expires_in: 900)
    #
    # @example Decode and verify
    #   token = ApiClient::Jwt::Token.new(
    #     algorithm: "RS256",
    #     key: public_key,
    #     issuer: "https://auth.example.com",
    #     audience: "my-api"
    #   )
    #   payload, header = token.decode(jwt_string)
    #
    class Token
      attr_reader :algorithm, :key, :issuer, :audience

      # @param algorithm [String, Symbol] Signing algorithm (RS256, ES256, etc.)
      # @param key [OpenSSL::PKey, JWT::JWK, String] Signing/verification key
      # @param issuer [String, nil] Expected issuer (iss claim)
      # @param audience [String, Array<String>, nil] Expected audience (aud claim)
      # @param allow_hmac [Boolean] Allow HMAC algorithms (not recommended)
      def initialize(algorithm:, key:, issuer: nil, audience: nil, allow_hmac: false)
        Auditor.require_jwt!
        Auditor.validate_algorithm!(algorithm, allow_hmac: allow_hmac)

        @algorithm = algorithm.to_s.upcase.freeze
        @key = key
        @issuer = issuer&.freeze
        @audience = audience.is_a?(Array) ? audience.freeze : audience&.freeze
        @allow_hmac = allow_hmac

        # Cache key-related computations at initialization
        @signing_key = compute_signing_key
        @verification_key = compute_verification_key
        @key_id = compute_key_id&.freeze
        @header_fields = build_header_fields.freeze
        @decode_options = build_decode_options.freeze

        validate_key_for_hmac! if @algorithm.start_with?("HS")
      end

      # Encode payload into JWT
      # @param payload [Hash] Claims to encode
      # @param expires_in [Integer] Seconds until expiration (default: 900 = 15 min)
      # @param issued_at [Time, Integer, nil] Override iat claim
      # @param not_before [Time, Integer, nil] nbf claim
      # @param jwt_id [String, nil] Override jti claim (default: UUID)
      # @param extra_claims [Hash] Additional claims to merge
      # @return [String] Encoded JWT
      def encode(
        payload, expires_in: 900, issued_at: nil,
        not_before: nil, jwt_id: nil, **extra_claims
      )
        full_payload = build_claims(payload, expires_in:, issued_at:, not_before:, jwt_id:)
        full_payload.merge!(extra_claims)
        full_payload.compact!

        ::JWT.encode(full_payload, @signing_key, @algorithm, @header_fields)
      end

      # Decode and verify JWT
      # @param token [String] Encoded JWT
      # @param leeway [Integer] Clock skew tolerance in seconds (default: 30)
      # @param verify_expiration [Boolean] Verify exp claim (default: true)
      # @param required_claims [Array<String>] Claims that must be present
      # @return [Array<Hash, Hash>] [payload, header]
      # @raise [TokenVerificationError] if verification fails
      def decode(token, leeway: 30, verify_expiration: true, required_claims: nil)
        options = @decode_options.merge(
          exp_leeway: leeway,
          nbf_leeway: leeway,
          verify_expiration: verify_expiration
        )

        options[:required_claims] = required_claims if required_claims

        ::JWT.decode(token, @verification_key, true, options)
      rescue ::JWT::DecodeError, ::JWT::VerificationError, ::JWT::ExpiredSignature,
        ::JWT::ImmatureSignature, ::JWT::InvalidIssuerError,
        ::JWT::InvalidAudError, ::JWT::InvalidSubError => e
        raise TokenVerificationError.new(e)
      end

      # Decode without verification (for inspection only)
      # @param token [String] Encoded JWT
      # @return [Array<Hash, Hash>] [payload, header]
      # @note Use with caution - does not verify signature
      def decode_unverified(token)
        ::JWT.decode(token, nil, false)
      end

      # Extract header without verification
      # @param token [String] Encoded JWT
      # @return [Hash] Header claims
      def peek_header(token)
        ::JWT.decode(token, nil, false).last
      end

      # Extract kid from token header
      # @param token [String] Encoded JWT
      # @return [String, nil] Key ID
      def extract_kid(token)
        peek_header(token)["kid"]
      end

      private

      def compute_signing_key
        if @key.respond_to?(:signing_key)
          @key.signing_key
        else
          @key
        end
      end

      def build_claims(payload, expires_in:, issued_at:, not_before:, jwt_id:)
        iat = normalize_time(issued_at) || Time.now.to_i

        claims = payload.merge(
          exp: iat + expires_in,
          iat: iat,
          jti: jwt_id || SecureRandom.uuid
        )

        claims[:iss] = @issuer if @issuer
        claims[:aud] = @audience if @audience
        claims[:nbf] = normalize_time(not_before) if not_before
        claims
      end

      def compute_verification_key
        if @key.respond_to?(:verify_key)
          @key.verify_key
        elsif @key.respond_to?(:public_key)
          @key.public_key
        else
          @key
        end
      end

      def build_header_fields
        fields = {typ: "JWT"}
        fields[:kid] = @key_id if @key_id
        fields
      end

      def compute_key_id
        return @key.kid if @key.respond_to?(:kid)
        return nil unless @key.respond_to?(:[])
        return nil if @key.is_a?(String)

        @key[:kid] || (@key.is_a?(Hash) && @key["kid"])
      end

      def build_decode_options
        {
          algorithm: @algorithm,
          verify_iss: !@issuer.nil?,
          verify_aud: !@audience.nil?,
          iss: @issuer,
          aud: @audience
        }.compact
      end

      def normalize_time(time)
        case time
        when Time then time.to_i
        when Integer then time
        when nil then nil
        else time.to_i
        end
      end

      def validate_key_for_hmac!
        return unless @key.is_a?(String)

        Auditor.validate_secret_strength!(@key)
      end
    end
  end
end
