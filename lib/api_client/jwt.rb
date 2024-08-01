require_relative "jwt/errors"
require_relative "jwt/auditor"

module ApiClient
  # JWT/JWK/JWKS support for ApiClient
  #
  # This module provides optional JWT functionality when the jwt gem is available.
  # All components enforce security best practices from RFC 8725.
  #
  # Components are loaded via autoload when first accessed.
  #
  # @example Check availability
  #   ApiClient::Jwt.available?  # => true if jwt gem installed
  #
  # @example Encode tokens
  #   token = ApiClient::Jwt::Token.new(algorithm: "RS256", key: private_key)
  #   jwt = token.encode({ sub: "user123" })
  #
  # @example Verify with JWKS
  #   jwks = ApiClient::Jwt::JwksClient.new(
  #     jwks_uri: "https://auth.example.com/.well-known/jwks.json"
  #   )
  #   JWT.decode(jwt, nil, true, { algorithms: ["RS256"], jwks: jwks.to_loader })
  #
  module Jwt
    autoload :Token, "api_client/jwt/token"
    autoload :JwksClient, "api_client/jwt/jwks_client"
    autoload :KeyStore, "api_client/jwt/key_store"
    autoload :Authenticator, "api_client/jwt/authenticator"

    class << self
      # Check if JWT functionality is available
      # @return [Boolean]
      def available?
        Auditor.available?
      end

      # Require JWT gem, raising if unavailable
      # @raise [JwtUnavailableError]
      def require!
        Auditor.require_jwt!
      end
    end
  end
end
