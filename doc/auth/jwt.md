---
title: JWT/JWK/JWKS Support
description: Token-based authentication with RFC 8725 security best practices
related_files:
  - lib/api_client/jwt.rb
  - lib/api_client/jwt/*.rb
semantic_version: "1.0"
last_updated: 2026-02-06
---
ApiClient provides optional JWT (JSON Web Token) support for token-based
authentication workflows. This feature requires the `jwt` gem.

## Installation

Add the jwt gem to your Gemfile:

```ruby
gem 'jwt', '>= 2.7'
```

## Quick Start

```ruby
require 'api_client'
require 'api_client/jwt'

# Check if JWT support is available
ApiClient::Jwt.available?  # => true

# Create a token encoder/decoder
key = OpenSSL::PKey::RSA.generate(2048)
token = ApiClient::Jwt::Token.new(
  algorithm: 'RS256',
  key: key,
  issuer: 'https://auth.example.com',
  audience: 'my-api'
)

# Encode a token
jwt = token.encode({ sub: 'user123', role: 'admin' })

# Decode and verify
payload, header = token.decode(jwt)
```

## Components

### Auditor

Security auditor that validates algorithms, JWK structure, and secret strength.

```ruby
# Check JWT gem availability
ApiClient::Jwt::Auditor.available?  # => true/false
ApiClient::Jwt::Auditor.require_jwt!  # raises JwtUnavailableError if unavailable

# Check algorithm security (raising)
ApiClient::Jwt::Auditor.validate_algorithm!('RS256')  # => true
ApiClient::Jwt::Auditor.validate_algorithm!('none')   # raises InvalidAlgorithmError

# Check algorithm security (non-raising)
ApiClient::Jwt::Auditor.algorithm_allowed?('RS256')  # => true
ApiClient::Jwt::Auditor.algorithm_allowed?('none')   # => false

# List allowed algorithms
ApiClient::Jwt::Auditor.allowed_algorithms  # => ["RS256", "RS384", ...]
ApiClient::Jwt::Auditor.allowed_algorithms(include_hmac: true)  # includes HS*

# Validate JWK structure
ApiClient::Jwt::Auditor.validate_jwk!(jwk_hash, 'RS256')

# Validate HMAC secret strength (>= 32 bytes required)
ApiClient::Jwt::Auditor.validate_secret_strength!(secret)

# Compute RFC 7638 thumbprint
thumbprint = ApiClient::Jwt::Auditor.thumbprint(jwk)
```

#### Allowed Algorithms

By default, only asymmetric algorithms are allowed:

| Algorithm           | Type    | Status           |
|---------------------|---------|------------------|
| RS256, RS384, RS512 | RSA     | Allowed          |
| ES256, ES384, ES512 | ECDSA   | Allowed          |
| PS256, PS384, PS512 | RSA-PSS | Allowed          |
| HS256, HS384, HS512 | HMAC    | Forbidden (1)    |
| none                | None    | Always forbidden |

#### Notes

1. override with `allow_hmac: true`

### Token

JWT encoder/decoder with security best practices enforced.

```ruby
# Asymmetric (recommended)
private_key = OpenSSL::PKey::RSA.generate(2048)
token = ApiClient::Jwt::Token.new(
  algorithm: 'RS256',
  key: private_key,
  issuer: 'https://auth.example.com',
  audience: 'my-api'
)

# Encode with automatic claims
jwt = token.encode(
  { sub: 'user123', role: 'admin' },
  expires_in: 900,        # 15 minutes (default)
  not_before: Time.now    # optional nbf claim
)

# Decode with strict verification
payload, header = token.decode(jwt, leeway: 30)

# Decode with required claims validation
payload, header = token.decode(jwt, required_claims: %w[sub role])

# Decode without verification (inspection only - use with caution)
payload, header = token.decode_unverified(jwt)

# Extract header/kid without verification
header = token.peek_header(jwt)
kid = token.extract_kid(jwt)
```

#### Automatic Claims

When encoding, these claims are automatically added:

| Claim | Description     | Default            |
|-------|-----------------|--------------------|
| `exp` | Expiration time | `iat + expires_in` |
| `iat` | Issued at       | Current time       |
| `jti` | JWT ID          | UUID               |
| `iss` | Issuer          | From constructor   |
| `aud` | Audience        | From constructor   |

### JwksClient

JWKS endpoint client with caching and automatic refresh.

```ruby
client = ApiClient::Jwt::JwksClient.new(
  jwks_uri: 'https://auth.example.com/.well-known/jwks.json',
  ttl: 600,                          # Cache TTL (default: 10 minutes)
  allowed_algorithms: %w[RS256 ES256] # Optional filter
)

# Get key by kid (raises KeyNotFoundError if not found)
key = client.key(kid: 'key-123')

# Get key by kid (returns nil if not found)
key = client.key_or_nil(kid: 'key-123')

# Force cache refresh
client.refresh!(force: true)

# Check cache status
client.stale?        # => true/false
client.cached_kids   # => ["key-123", "key-456"]
client.clear!        # Clear cache

# Use as JWT.decode loader
JWT.decode(token, nil, true, {
  algorithms: ['RS256'],
  jwks: client.to_loader
})

# Get all keys as JWT::JWK::Set
jwks_set = client.jwks_set
```

#### Caching Behavior

- Keys are cached for `ttl` seconds (default: 600)
- On `kid_not_found`, cache is refreshed (rate-limited to every 5 minutes via `REFRESH_GRACE_PERIOD`)
- On fetch failure, stale cache is preserved
- Keys with `use: "enc"` are filtered out (only `use: "sig"` kept)

### KeyStore

Thread-safe in-memory key storage with rotation support.

Key states: `:active`, `:signing`, `:retired`

```ruby
store = ApiClient::Jwt::KeyStore.new

# Add keys with state
store.add(private_key, kid: 'key-2025-01', state: :signing)
store.add(new_key, kid: 'key-2025-04', state: :active)

# Get keys
signing_key = store.signing_key
signing_kid = store.signing_kid
verification_key = store.get('key-2025-01')   # returns nil if not found
verification_key = store.get!('key-2025-01')  # raises KeyNotFoundError

# Query store
store.key?('key-2025-01')           # => true
store.kids                          # => ["key-2025-01", "key-2025-04"]
store.kids(state: :signing)         # => ["key-2025-01"]
store.size                          # => 2
store.empty?                        # => false

# Key rotation
store.activate('key-2025-04')    # Make new key the signing key
store.retire('key-2025-01')      # Mark old key as retired
store.remove('key-2025-01')      # Remove after tokens expire

# Export as JWKS
jwks = store.to_jwks
jwks = store.to_jwks(include_retired: false)

# Import from JWKS
store.import_jwks(jwks_hash, state: :active)

# Clear all keys
store.clear!
```

### Authenticator

Request authenticator for Bearer token injection.

```ruby
# Static token
auth = ApiClient::Jwt::Authenticator.new(token_provider: 'eyJ...')
client = ApiClient.new(default_headers: auth.headers)

# Dynamic token (refreshed per-request)
signer = ApiClient::Jwt::Token.new(algorithm: 'RS256', key: private_key)
auth = ApiClient::Jwt::Authenticator.new(
  token_provider: -> { signer.encode({ sub: 'service-account' }) }
)

# As Faraday middleware
Faraday.new do |f|
  f.use ApiClient::Jwt::Authenticator.middleware(
    token_provider: -> { generate_token }
  )
end
```

## Configuration

Configure JWT settings globally:

```ruby
ApiClient.configure do |config|
  config.jwt do |jwt|
    jwt.algorithm = 'RS256'
    jwt.issuer = 'https://auth.example.com'
    jwt.audience = 'my-api'
    jwt.jwks_uri = 'https://auth.example.com/.well-known/jwks.json'
    jwt.jwks_ttl = 600
    jwt.token_lifetime = 900
    jwt.leeway = 30
    jwt.allow_hmac = false
  end
end
```

## Security Best Practices

This implementation enforces RFC 8725 recommendations:

1. **No "none" algorithm** - Always rejected
2. **Strict algorithm enforcement** - Never trust the header's `alg` claim
3. **HMAC discouraged** - Use asymmetric algorithms for API-to-API
4. **Mandatory expiration** - `exp` claim always added
5. **Strong secrets** - HMAC secrets must be >= 32 bytes
6. **JWKS caching** - Rate-limited refresh prevents DoS

## Key Rotation

Supports zero-downtime 4-phase key rotation:

```ruby
store = ApiClient::Jwt::KeyStore.new

# Phase 1: Normal operation
store.add(current_key, kid: 'key-2025-01', state: :signing)

# Phase 2: Introduce new key (both published)
store.add(new_key, kid: 'key-2025-04', state: :active)

# Phase 3: Switch signing key (both still valid for verification)
store.activate('key-2025-04')
store.retire('key-2025-01')

# Phase 4: Remove old key (after max token lifetime)
store.remove('key-2025-01')
```

## Error Handling

```ruby
begin
  payload, header = token.decode(jwt)
rescue ApiClient::Jwt::TokenVerificationError => e
  # Signature invalid, expired, wrong issuer/audience
  logger.warn "Token verification failed: #{e.message}"
rescue ApiClient::Jwt::KeyNotFoundError => e
  # kid not found in JWKS
  logger.error "Key #{e.kid} not found"
rescue ApiClient::Jwt::JwksFetchError => e
  # JWKS endpoint unavailable
  logger.error "JWKS fetch failed: #{e.uri} (#{e.status})"
end
```

## Examples

### Verify Incoming Tokens

```ruby
jwks_client = ApiClient::Jwt::JwksClient.new(
  jwks_uri: 'https://auth.example.com/.well-known/jwks.json'
)

def verify_token(jwt)
  JWT.decode(jwt, nil, true, {
    algorithms: ['RS256'],
    jwks: jwks_client.to_loader,
    iss: 'https://auth.example.com',
    aud: 'my-api',
    verify_iss: true,
    verify_aud: true
  })
end
```

### Sign Outgoing Requests

```ruby
private_key = OpenSSL::PKey::RSA.new(ENV['PRIVATE_KEY_PEM'])
signer = ApiClient::Jwt::Token.new(
  algorithm: 'RS256',
  key: private_key,
  issuer: 'my-service'
)

auth = ApiClient::Jwt::Authenticator.new(
  token_provider: -> { signer.encode({ sub: 'my-service' }) }
)

client = ApiClient.new(
  service_uri: 'https://api.example.com',
  default_headers: auth.headers
)

response = client.get('/protected-resource')
```

### Publish JWKS Endpoint

```ruby
# In a Rails controller
class JwksController < ApplicationController
  def show
    render json: key_store.to_jwks(include_retired: false)
  end

  private

  def key_store
    @key_store ||= Rails.application.config.jwt_key_store
  end
end
```
