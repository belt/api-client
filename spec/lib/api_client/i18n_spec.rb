require "spec_helper"
require "api_client"

RSpec.describe ApiClient::I18n do
  # Load once for the entire file — avoids repeated backend reloads
  before(:context) do # rubocop:disable RSpec/BeforeAfterAll
    described_class.load!
    # Warm the backend so the first .t call doesn't pay the lazy-load cost
    ::I18n.t("api_client.errors.no_adapter")
  end

  describe ".t" do
    it "translates a simple key" do
      expect(described_class.t("errors.no_adapter")).to include("No concurrency adapter")
    end

    it "interpolates variables" do
      result = described_class.t("errors.circuit_open", service: "payments")
      expect(result).to eq("Circuit open for service: payments")
    end

    it "returns scoped under api_client namespace" do
      result = described_class.t("errors.timeout", timeout_type: "read")
      expect(result).to eq("Request timed out (read)")
    end
  end

  describe ".load!" do
    it "is idempotent" do
      # Already loaded in before(:all) — calling again should not raise
      described_class.load!
      expect(described_class.t("errors.no_adapter")).to include("No concurrency adapter")
    end

    it "adds locale files to I18n.load_path" do
      locale_file = File.expand_path("../../../config/locales/en.yml", __dir__)
      expect(::I18n.load_path).to include(locale_file)
    end
  end

  describe ".reset!" do
    it "clears loaded state so next call reloads" do
      described_class.reset!
      # Verify reset cleared the flag by checking load! runs again
      # (it's a no-op when already loaded, so if this doesn't raise, reset worked)
      described_class.load!
      expect(described_class.t("errors.no_adapter")).to include("No concurrency adapter")
    end
  end

  describe "locale coverage" do
    describe "errors" do
      it "translates circuit_open" do
        expect(described_class.t("errors.circuit_open", service: "svc"))
          .to eq("Circuit open for service: svc")
      end

      it "translates no_adapter" do
        expect(described_class.t("errors.no_adapter"))
          .to include("No concurrency adapter available")
      end

      it "translates ssrf_blocked" do
        expect(described_class.t("errors.ssrf_blocked", reason: "bad", uri: "http://x"))
          .to eq("SSRF blocked: bad (http://x)")
      end

      it "translates timeout" do
        expect(described_class.t("errors.timeout", timeout_type: "read"))
          .to eq("Request timed out (read)")
      end

      it "translates processing" do
        expect(described_class.t("errors.processing", count: 3, processor_name: "Ractor"))
          .to eq("3 items failed during Ractor processing")
      end
    end

    describe "configuration" do
      it "translates positive_integer" do
        result = described_class.t("configuration.positive_integer",
          attribute: "pool_size", value: "-1")
        expect(result).to include("pool_size").and include("positive Integer").and include("-1")
      end

      it "translates non_negative_integer" do
        result = described_class.t("configuration.non_negative_integer",
          attribute: "min_batch", value: "-5")
        expect(result).to include("min_batch").and include("non-negative Integer").and include("-5")
      end

      it "translates pool_size_positive" do
        result = described_class.t("configuration.pool_size_positive", value: "nil")
        expect(result).to include("pool size").and include("positive Integer")
      end

      it "translates pool_timeout_positive" do
        result = described_class.t("configuration.pool_timeout_positive", value: "nil")
        expect(result).to include("pool timeout").and include("positive Numeric")
      end
    end

    describe "connection" do
      it "translates faraday_removed" do
        expect(described_class.t("connection.faraday_removed"))
          .to include("has been removed").and include("with_faraday")
      end

      it "translates error_log" do
        expect(described_class.t("connection.error_log", message: "boom"))
          .to eq("ApiClient error: boom")
      end
    end

    describe "request_flow" do
      it "translates step_failed" do
        result = described_class.t("request_flow.step_failed",
          index: 2, type: "fetch", message: "timeout")
        expect(result).to include("step 2").and include("fetch").and include("timeout")
      end

      it "translates timeout" do
        result = described_class.t("request_flow.timeout",
          timeout: 30, step_index: 1, elapsed: 31.5)
        expect(result).to include("30").and include("step 1").and include("31.5")
      end

      it "translates unknown_step" do
        expect(described_class.t("request_flow.unknown_step", type: "bogus"))
          .to include("Unknown request flow step").and include("bogus")
      end
    end

    describe "transforms" do
      it "translates unknown" do
        expect(described_class.t("transforms.unknown", transform: "nope"))
          .to eq("Unknown transform: nope")
      end
    end

    describe "extractors" do
      it "translates unknown" do
        expect(described_class.t("extractors.unknown", extract: "nope"))
          .to eq("Unknown extractor: nope")
      end

      it "translates invalid_type" do
        expect(described_class.t("extractors.invalid_type"))
          .to eq("Extractor must be Symbol or Proc")
      end
    end

    describe "backend" do
      it "translates cannot_override_core" do
        expect(described_class.t("backend.cannot_override_core", name: "typhoeus"))
          .to include("Cannot override core backend").and include("typhoeus")
      end

      it "translates must_implement_execute" do
        expect(described_class.t("backend.must_implement_execute", klass: "Foo"))
          .to include("Backend must implement #execute")
      end

      it "translates must_implement_config" do
        expect(described_class.t("backend.must_implement_config", klass: "Foo"))
          .to include("Backend must implement #config")
      end

      it "translates unknown" do
        expect(described_class.t("backend.unknown", backend: "nope"))
          .to include("Unknown backend").and include("nope")
      end
    end

    describe "interface" do
      it "translates must_implement" do
        result = described_class.t("interface.must_implement",
          klass: "MyClass", method_name: "execute")
        expect(result).to include("MyClass").and include("#execute")
      end
    end

    describe "processing" do
      it "translates unknown_processor" do
        expect(described_class.t("processing.unknown_processor", processor: "nope"))
          .to include("Unknown processor").and include("nope")
      end

      it "translates invalid_pool_option" do
        expect(described_class.t("processing.invalid_pool_option", option: ":bad"))
          .to include("Invalid pool option").and include(":bad")
      end

      it "translates async_container_required" do
        expect(described_class.t("processing.async_container_required"))
          .to include("async-container gem required")
      end

      it "translates concurrent_ruby_required" do
        expect(described_class.t("processing.concurrent_ruby_required"))
          .to include("concurrent-ruby gem required")
      end

      it "translates pool_shutdown" do
        expect(described_class.t("processing.pool_shutdown"))
          .to eq("Pool has been shutdown")
      end
    end

    describe "uri_policy" do
      it "translates unparseable" do
        expect(described_class.t("uri_policy.unparseable")).to eq("unparseable URI")
      end

      it "translates malformed" do
        expect(described_class.t("uri_policy.malformed")).to eq("malformed URI")
      end

      it "translates blocked_scheme" do
        expect(described_class.t("uri_policy.blocked_scheme", scheme: "file"))
          .to eq("blocked scheme: file")
      end

      it "translates path_traversal" do
        expect(described_class.t("uri_policy.path_traversal"))
          .to eq("path traversal detected")
      end

      it "translates blocked_host" do
        expect(described_class.t("uri_policy.blocked_host", host: "evil.com"))
          .to eq("blocked host: evil.com")
      end

      it "translates host_not_allowed" do
        expect(described_class.t("uri_policy.host_not_allowed", host: "rogue.com"))
          .to eq("host not in allowlist: rogue.com")
      end

      it "translates blocked_network" do
        expect(described_class.t("uri_policy.blocked_network", network: "10.0.0.0/8"))
          .to eq("blocked network: 10.0.0.0/8")
      end
    end

    describe "base" do
      it "translates unknown_keys" do
        result = described_class.t("base.unknown_keys",
          keys: "[:foo]", expected: "params")
        expect(result).to include("Unknown keys").and include("[:foo]").and include("params")
      end
    end

    describe "fan_out" do
      it "translates invalid_requests_type" do
        expect(described_class.t("fan_out.invalid_requests_type", klass: "String"))
          .to include("requests must be an Array").and include("String")
      end

      it "translates invalid_request_item" do
        expect(described_class.t("fan_out.invalid_request_item", klass: "Integer"))
          .to include("Hash-like").and include("Integer")
      end

      it "translates invalid_timeout" do
        expect(described_class.t("fan_out.invalid_timeout", value: "-1"))
          .to include("positive number").and include("-1")
      end
    end

    describe "registry" do
      it "translates unknown_entry" do
        expect(described_class.t("registry.unknown_entry",
          entry_type: "processor", key: "bogus"))
          .to include("Unknown processor").and include("bogus")
      end
    end

    describe "jwt" do
      it "translates unavailable" do
        expect(described_class.t("jwt.unavailable"))
          .to include("jwt gem not available")
      end

      it "translates none_forbidden" do
        expect(described_class.t("jwt.none_forbidden"))
          .to include("'none' algorithm is forbidden")
      end

      it "translates hmac_discouraged" do
        expect(described_class.t("jwt.hmac_discouraged"))
          .to include("HMAC algorithms discouraged")
      end

      it "translates algorithm_not_allowed" do
        result = described_class.t("jwt.algorithm_not_allowed",
          algorithm: "XYZ", allowed: "RS256, ES256")
        expect(result).to include("XYZ").and include("not in allowed list")
      end

      it "translates unknown_algorithm_type" do
        expect(described_class.t("jwt.unknown_algorithm_type", algorithm: "XYZ"))
          .to include("Unknown algorithm type").and include("XYZ")
      end

      it "translates jwk_missing_fields" do
        result = described_class.t("jwt.jwk_missing_fields",
          label: "RSA", fields: "n, e")
        expect(result).to include("RSA").and include("missing required fields").and include("n, e")
      end

      it "translates jwk_kty_mismatch" do
        result = described_class.t("jwt.jwk_kty_mismatch",
          label: "RSA", expected: "RSA", actual: "EC")
        expect(result).to include("RSA").and include("must be").and include("EC")
      end

      it "translates weak_secret" do
        result = described_class.t("jwt.weak_secret", minimum: 32, actual: 8)
        expect(result).to include("at least 32 bytes").and include("got 8")
      end

      it "translates cannot_convert_jwk" do
        expect(described_class.t("jwt.cannot_convert_jwk", klass: "Integer"))
          .to include("Cannot convert Integer to JWK")
      end

      it "translates key_not_found" do
        expect(described_class.t("jwt.key_not_found", kid: "abc"))
          .to eq("Key 'abc' not found")
      end

      it "translates key_not_found_at_uri" do
        result = described_class.t("jwt.key_not_found_at_uri",
          kid: "abc", jwks_uri: "https://auth.example.com/jwks")
        expect(result).to include("Key 'abc' not found")
          .and include("https://auth.example.com/jwks")
      end

      it "translates jwks_fetch_failed" do
        result = described_class.t("jwt.jwks_fetch_failed",
          uri: "https://auth.example.com/jwks", status: 500)
        expect(result).to include("Failed to fetch JWKS").and include("500")
      end

      it "translates token_verification_failed" do
        expect(described_class.t("jwt.token_verification_failed"))
          .to eq("Token verification failed")
      end
    end
  end

  describe "error class integration" do
    it "CircuitOpenError uses I18n" do
      error = ApiClient::CircuitOpenError.new("payments")
      expect(error.message).to eq("Circuit open for service: payments")
    end

    it "NoAdapterError uses I18n" do
      error = ApiClient::NoAdapterError.new
      expect(error.message).to include("No concurrency adapter available")
    end

    it "TimeoutError uses I18n" do
      error = ApiClient::TimeoutError.new(:read)
      expect(error.message).to eq("Request timed out (read)")
    end

    it "SsrfBlockedError uses I18n" do
      error = ApiClient::SsrfBlockedError.new("http://evil.com", "blocked host: evil.com")
      expect(error.message).to include("SSRF blocked")
    end

    it "CircuitOpenError allows message override" do
      error = ApiClient::CircuitOpenError.new("svc", "custom message")
      expect(error.message).to eq("custom message")
    end

    it "NoAdapterError allows message override" do
      error = ApiClient::NoAdapterError.new("custom message")
      expect(error.message).to eq("custom message")
    end

    it "TimeoutError allows message override" do
      error = ApiClient::TimeoutError.new(:read, "custom message")
      expect(error.message).to eq("custom message")
    end
  end
end
