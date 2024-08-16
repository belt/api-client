require_relative "auditor"
require_relative "errors"

module ApiClient
  module Jwt
    # Thread-safe in-memory key storage with rotation support
    #
    # Manages JWKs for signing and verification, supporting the 4-phase
    # key rotation pattern (introduce → activate → retire → remove).
    #
    # @example Basic usage
    #   store = ApiClient::Jwt::KeyStore.new
    #   store.add(jwk, kid: "key-2025-01")
    #   key = store.get("key-2025-01")
    #
    # @example Key rotation
    #   store.add(new_jwk, kid: "key-2025-04")      # Phase 2: introduce
    #   store.activate("key-2025-04")               # Phase 3: switch signing
    #   store.retire("key-2025-01")                 # Phase 3: mark old as retired
    #   store.remove("key-2025-01")                 # Phase 4: remove after TTL
    #
    class KeyStore
      # Key entry with metadata
      KeyEntry = Struct.new(
        :jwk, :kid, :algorithm, :state, :added_at, :retired_at,
        keyword_init: true
      ) do
        def active?
          state == :active
        end

        def retired?
          state == :retired
        end

        def signing_key?
          state == :signing
        end
      end

      # Key states
      STATES = %i[active signing retired].freeze

      def initialize
        Auditor.require_jwt!
        @keys = {}
        @signing_kid = nil
        @mutex = Mutex.new
      end

      # Add a key to the store
      # @param jwk [Hash, JWT::JWK, OpenSSL::PKey] Key to add
      # @param kid [String, nil] Key ID (auto-generated if nil)
      # @param algorithm [String, nil] Algorithm (inferred from key if nil)
      # @param state [Symbol] Initial state (:active, :signing)
      # @return [String] Key ID
      def add(jwk, kid: nil, algorithm: nil, state: :active)
        jwk_obj = normalize_jwk(jwk)
        key_id = kid || jwk_obj[:kid] || Auditor.thumbprint(jwk_obj)
        alg = algorithm || jwk_obj[:alg]

        entry = KeyEntry.new(
          jwk: jwk_obj,
          kid: key_id,
          algorithm: alg,
          state: state,
          added_at: Time.now,
          retired_at: nil
        )

        @mutex.synchronize do
          @keys[key_id] = entry
          @signing_kid = key_id if state == :signing
        end

        key_id
      end

      # Get key by ID
      # @param kid [String] Key ID
      # @return [JWT::JWK, nil]
      def get(kid)
        @mutex.synchronize { @keys[kid] }&.jwk
      end

      # Get key by ID, raising if not found
      # @param kid [String] Key ID
      # @return [JWT::JWK]
      # @raise [KeyNotFoundError]
      def get!(kid)
        get(kid) || raise(KeyNotFoundError.new(kid: kid))
      end

      # Get the current signing key
      # @return [JWT::JWK, nil]
      def signing_key
        @mutex.synchronize do
          return nil unless @signing_kid
          @keys[@signing_kid]&.jwk
        end
      end

      # Get signing key ID
      # @return [String, nil]
      def signing_kid
        @mutex.synchronize { @signing_kid }
      end

      # Set key as the active signing key
      # @param kid [String] Key ID
      # @raise [KeyNotFoundError] if key not in store
      def activate(kid)
        @mutex.synchronize do
          raise KeyNotFoundError.new(kid: kid) unless @keys.key?(kid)

          # Demote current signing key to active
          current_signing = @signing_kid && @keys[@signing_kid]
          current_signing.state = :active if current_signing

          @keys[kid].state = :signing
          @signing_kid = kid
        end
      end

      # Mark key as retired (still valid for verification, not signing)
      # @param kid [String] Key ID
      def retire(kid)
        @mutex.synchronize do
          entry = @keys[kid]
          return unless entry

          entry.state = :retired
          entry.retired_at = Time.now
          @signing_kid = nil if @signing_kid == kid
        end
      end

      # Remove key from store
      # @param kid [String] Key ID
      # @return [JWT::JWK, nil] Removed key
      def remove(kid)
        @mutex.synchronize do
          entry = @keys.delete(kid)
          @signing_kid = nil if @signing_kid == kid
          entry&.jwk
        end
      end

      # List all key IDs
      # @param state [Symbol, nil] Filter by state
      # @return [Array<String>]
      def kids(state: nil)
        @mutex.synchronize do
          if state
            @keys.each_with_object([]) { |(kid, entry), arr| arr << kid if entry.state == state }
          else
            @keys.keys.dup
          end
        end
      end

      # Check if key exists
      # @param kid [String] Key ID
      # @return [Boolean]
      def key?(kid)
        @mutex.synchronize { @keys.key?(kid) }
      end

      # Get all keys as JWKS hash
      # @param include_retired [Boolean] Include retired keys
      # @return [Hash] JWKS format { keys: [...] }
      def to_jwks(include_retired: true)
        @mutex.synchronize do
          exported = @keys.values.filter_map do |entry|
            entry.jwk.export unless !include_retired && entry.retired?
          end
          {keys: exported}
        end
      end

      # Import keys from JWKS hash
      # @param jwks [Hash] JWKS format { keys: [...] }
      # @param state [Symbol] State for imported keys
      # @return [Array<String>] Imported key IDs
      def import_jwks(jwks, state: :active)
        keys_array = jwks[:keys] || jwks["keys"] || []

        keys_array.map do |jwk_hash|
          add(jwk_hash, state: state)
        end
      end

      # Clear all keys
      def clear!
        @mutex.synchronize do
          @keys.clear
          @signing_kid = nil
        end
      end

      # Number of keys in store
      # @return [Integer]
      def size
        @mutex.synchronize { @keys.size }
      end

      # Check if store is empty
      # @return [Boolean]
      def empty?
        @mutex.synchronize { @keys.empty? }
      end

      private

      def normalize_jwk(jwk)
        case jwk
        when ::JWT::JWK::KeyBase
          jwk
        when OpenSSL::PKey::RSA, OpenSSL::PKey::EC
          ::JWT::JWK.new(jwk)
        when Hash
          ::JWT::JWK.new(jwk)
        else
          raise InvalidJwkError, I18n.t("jwt.cannot_convert_jwk", klass: jwk.class)
        end
      end
    end
  end
end
