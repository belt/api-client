---
title: "ApiClient Architecture"
audience_chain:
  - "developer"
  - "maintainer"
semantic_version: "1.0"
last_updated_at: "2026-02-06"
---
# ApiClient Architecture

HTTP client with concurrent requests, circuit breaker, request flow workflows,
streaming fan-out, and JWT authentication built on Faraday.

## System Overview

```text
┌─────────────────────────────────────────────────────────────────────┐
│                         ApiClient Module                            │
│  • Module-level HTTP methods (get, post, put, patch, delete, etc.)  │
│  • Global configuration (thread-safe, mutex-protected)              │
│  • Zeitwerk autoloading (adapters/JWT ignored, loaded on-demand)    │
│  • YJIT auto-enable (Ruby 3.1+)                                     │
└─────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────┐
│                         ApiClient::Base                             │
│  • Faraday-compatible interface (url:, positional params, blocks)   │
│  • HTTP verbs (get/post/put/patch/delete/head/trace)                │
│  • batch() → concurrent requests via Orchestrators::Batch           │
│  • sequential() → one-by-one via Orchestrators::Sequential          │
│  • request_flow() → workflow chains (fetch → fan_out → collect)     │
│  • Circuit breaker integration (with_circuit wrapper)               │
└─────────────────────────────────────────────────────────────────────┘
                    │                           │
        ┌───────────┴───────────┐   ┌───────────┴───────────┐
        ▼                       ▼   ▼                       ▼
┌───────────────┐    ┌───────────────────────────────────────────────┐
│  Connection   │    │              Orchestrators                    │
│  (Faraday)    │    │  ┌─────────────┐  ┌─────────────────────────┐ │
│  • Middleware │    │  │ Sequential  │  │ Batch (auto-detect)     │ │
│  • Timeouts   │    │  │ (one-by-one)│  │ (concurrent dispatch)   │ │
│  • Pooling    │    │  └─────────────┘  └───────────┬─────────────┘ │
│  • Hooks      │    └──────────────────────────────┬┴───────────────┘
└───────────────┘                                   │
                     ┌──────────────────────────────┴─────────────────┐
                     │           Backend::Registry                    │
                     │  Detection order (I/O-bound HTTP):             │
                     │  1. Typhoeus   → HTTP/2, libcurl Hydra         │
                     │  2. Async      → Fiber-based (Ruby 3+)         │
                     │  3. Concurrent → Thread pool                   │
                     │  4. Sequential → Fallback                      │
                     │  + Custom backends via Backend.register()      │
                     └────────────────────────────────────────────────┘
```

## RequestFlow Architecture

```text
┌─────────────────────────────────────────────────────────────────────┐
│                           RequestFlow                               │
│                                                                     │
│  Steps:                                                             │
│  fetch() → then() → filter() → fan_out() → map()                    │
│  → parallel_map() / async_map() / concurrent_map() / process()      │
│  → collect()                                                        │
│                                                                     │
│  fan_out() ──────────────────────┐                                  │
│    │                             │                                  │
│    ▼                             ▼                                  │
│  Streaming::FanOutExecutor    Orchestrators::Batch                  │
│  (on_ready: :stream)          (on_ready: :batch)                    │
│  • Async semaphore            • Backend auto-detect                 │
│  • Backpressure               • Wait for all                        │
│  • Per-request retry                                                │
│  • FailureStrategy                                                  │
│                                                                     │
│  parallel_map() / async_map() / concurrent_map() / process()        │
│    │                                                                │
│    ▼                                                                │
│  Processing::Registry                                               │
│  Detection order (CPU-bound):                                       │
│  1. Ractor     → True parallelism, isolated memory                  │
│  2. Async      → Fork-based (async-container)                       │
│  3. Concurrent → Thread pool                                        │
│  4. Sequential → Fallback                                           │
└─────────────────────────────────────────────────────────────────────┘
```

## Cross-Cutting Concerns

```text
┌─────────────────────────────────────────────────────────────────────┐
│  • Circuit (Stoplight/Null)  → Fail-fast protection (optional dep)  │
│  • Poolable (ConnectionPool) → Thread-safe connection reuse         │
│  • Hooks (AS::Notifications) → Observability (30+ event types)      │
│  • JWT (optional)            → Token auth + JWKS + KeyStore         │
│  • Profiling (StackProf)     → CPU/wall/allocation profiling        │
│  • Transforms                → Shared extract + transform pipeline  │
│  • Errors                    → Custom exception hierarchy           │
│  • Middleware (OTel)         → X-Request-Faraday-Start header       │
└─────────────────────────────────────────────────────────────────────┘
```

### Integration Matrix

Components integrate cross-cutting concerns as follows:

#### Circuit Breaker

- Base — wraps all HTTP operations in circuit via `with_circuit`
- Circuit.new — factory returns `Circuit` (Stoplight) or `NullCircuit`
- NullCircuit — pass-through when Stoplight is absent; same interface, no protection
- Connection — error handling feeds circuit state
- Circuit — `redis_pool` config prefers ConnectionPool over raw Redis client

#### Connection Pooling (Poolable)

- Poolable — shared concern providing `build_pool` and `with_pooled_connection`
- Connection — pools Faraday instances; requests checkout/checkin via pool
- ConcurrentAdapter — pools Faraday connections; each thread checks out from pool
- NullPool — pass-through when pooling disabled; same `.with` interface
- PoolConfig — size (default: nproc), timeout (5s), enabled (true)

#### Hooks (AS::Notifications)

- Connection — `request_start`, `request_complete`, `request_error`
- Adapters — `batch_start`, `batch_complete`, `batch_slow` (via Instrumentation mixin)
- Orchestrators — `batch_start`, `batch_complete` (Sequential includes Instrumentation)
- RequestFlow — `request_flow_start`, `request_flow_complete`, `request_flow_step`
- Processors — `ractor_start/complete/error`, `async_processor_*`, `concurrent_processor_*`
- FanOutExecutor — `fan_out_start`, `fan_out_complete`, `fan_out_retry`, `fan_out_error`
- Circuit — `circuit_open`, `circuit_close`, `circuit_half_open`, `circuit_rejected`
- Profiling — `profile_captured`, `request_slow`

#### JWT Authentication

- JWT::Authenticator — provides `headers` hash or Faraday middleware class
- JWT::Token — RFC 8725 encode/decode with algorithm enforcement
- JWT::JwksClient — JWKS endpoint with TTL caching and rate-limited refresh
- JWT::KeyStore — thread-safe key storage with 4-phase rotation
- JWT::Auditor — algorithm/JWK/secret validation
- Connection — accepts auth headers via `default_headers` config

#### Profiling

- Profiling.cpu/wall/allocations — manual profiling blocks (StackProf)
- Profiling.profile_if_slow — auto-capture slow operations
- Profiling::Middleware — Rack middleware for request profiling

#### Transforms

- Transforms::Recipe — Data.define for extract + transform pipeline
- Built-in extractors: `:body`, `:status`, `:headers`, `:identity`
- Built-in transforms: `:identity`, `:json`, `:sha256`
- Used by all processors via BaseProcessor

#### Errors

- CircuitOpenError — raised by Circuit when open
- TimeoutError — raised by Connection on timeout
- ProcessingError variants — raised by processors with partial results
- FanOutError — raised by streaming fan-out with partial results

## Key Design Decisions

Do one thing and do it really well. In this case, many things "API Client" and adjacent.
Be secure, performant, maintainable, flexible, solve the "API request" problem.
There are many concerns.

- **Faraday compat** — Same response objects, similar API (url:, positional params, block config)
- **Connection pooling** — ConnectionPool for thread-safe Faraday reuse; NullPool pass-through when disabled
- **HTTP concurrency** — Auto-detect best backend (Typhoeus > Async > Concurrent > Sequential)
- **Backend registry** — Plugin system for custom HTTP backends via Backend.register()
- **CPU parallelism** — Auto-detect best processor (Ractor > Async > Concurrent > Sequential)
- **Streaming fan-out** — Async-based with semaphore backpressure, per-request retry, configurable failure strategies
- **Circuit breaker** — Optional per-host circuits; NullCircuit pass-through when absent
- **Configuration** — Global + per-instance override pattern (retry, circuit, JWT, processor, pool)
- **Optional deps** — Leverage if available gems: backends, processing/transforms, JWT, Rails
- **Data classes** — `Data.define` for immutable value objects (ErrorStrategy, FailureStrategy, ProcessingContext, Recipe)
- **Registry pattern** — Shared `RegistryBase` memoized audit with opinionated/graceful fallback

## Operational Registries

**Backend::Registry** — I/O-bound HTTP batching

- Typhoeus → Async → Concurrent → Sequential
- Plugin support via Backend.register()

**Processing::Registry** — CPU-bound data processing

- Ractor → Async → Concurrent → Sequential

Extends `Concerns::RegistryBase` for memoized detection, availability checking,
and graceful fallback to sequential.

## Component Responsibilities

### Core

- **ApiClient** (`lib/api_client.rb`) — Module entry, global config, Zeitwerk setup, YJIT enable
- **Base** (`lib/api_client/base.rb`) — Client instance, HTTP verbs, batch/sequential/request_flow
- **Configuration** (`lib/api_client/configuration.rb`) — Settings, timeouts, nested configs (RetryConfig, CircuitConfig, JwtConfig, ProcessorConfig, PoolConfig)
- **Connection** (`lib/api_client/connection.rb`) — Faraday wrapper, middleware stack, request instrumentation, connection pooling via Poolable
- **HttpVerbs** (`lib/api_client/http_verbs.rb`) — Verb constants, method definition helpers (bodyless/body)

### Backend System

- **Backend** (`lib/api_client/backend.rb`) — Module entry, registry delegation
- **Backend::Interface** (`lib/api_client/backend/interface.rb`) — Contract for HTTP backends
- **Backend::Registry** (`lib/api_client/backend/registry.rb`) — Auto-detection, plugin support, core backend resolution

### Orchestrators

- **Sequential** (`lib/api_client/orchestrators/sequential.rb`) — One-by-one request execution with instrumentation
- **Batch** (`lib/api_client/orchestrators/batch.rb`) — Concurrent dispatch via auto-detected backend

### Backends (I/O-bound)

- **Base** (`lib/api_client/adapters/base.rb`) — Shared body encoding, error response building, header merging
- **Instrumentation** (`lib/api_client/adapters/instrumentation.rb`) — Batch timing and hooks mixin
- **TyphoeusAdapter** (`lib/api_client/adapters/typhoeus_adapter.rb`) — requires `gem 'typhoeus'`
- **AsyncAdapter** (`lib/api_client/adapters/async_adapter.rb`) — Ruby 3+ and `gem 'async-http'`
- **ConcurrentAdapter** (`lib/api_client/adapters/concurrent_adapter.rb`) — requires `gem 'concurrent-ruby'`; pools Faraday connections via Poolable

### Processors/Transforms (CPU-bound)

- **BaseProcessor** (`lib/api_client/processing/base_processor.rb`) — Shared extractors, sequential/parallel dispatch, error handling
- **Registry** (`lib/api_client/processing/registry.rb`) — Auto-detection and resolution
- **ErrorStrategy** (`lib/api_client/processing/error_strategy.rb`) — Data.define: fail_fast, collect, skip, replace
- **ProcessingContext** (`lib/api_client/processing/processing_context.rb`) — Data.define: indexed/sequential result collection
- **RactorProcessor** (`lib/api_client/processing/ractor_processor.rb`) — Ruby 3+ with Ractor
- **RactorPool** (`lib/api_client/processing/ractor_pool.rb`) — Fixed-size Ractor pool with work distribution
- **AsyncProcessor** (`lib/api_client/processing/async_processor.rb`) — requires `gem 'async-container'`
- **ConcurrentProcessor** (`lib/api_client/processing/concurrent_processor.rb`) — requires `gem 'concurrent-ruby'`

### RequestFlow

- **RequestFlow** (`lib/api_client/request_flow.rb`) — Workflow chaining (fetch → then → filter → fan_out → map → collect)
- **RequestFlow::Registry** (`lib/api_client/request_flow/registry.rb`) — NxtRegistry-based lazy-loading for processors and adapters
- **StepHelpers** (`lib/api_client/request_flow/step_helpers.rb`) — Shared step configuration and processor execution

### Streaming

- **FanOutExecutor** (`lib/api_client/streaming/fan_out_executor.rb`) — Async-based streaming fan-out with backpressure, per-request retry, configurable failure handling
- **FailureStrategy** (`lib/api_client/streaming/failure_strategy.rb`) — Data.define: fail_fast, collect, skip, callback

### Cross-Cutting

- **Circuit** (`lib/api_client/circuit.rb`) — Stoplight wrapper, fail-fast, fallback, error handler chaining
- **NullCircuit** (`lib/api_client/null_circuit.rb`) — Pass-through when Stoplight absent
- **Hooks** (`lib/api_client/hooks.rb`) — AS::Notifications instrumentation (30+ events) + custom hook dispatch
- **Errors** (`lib/api_client/errors.rb`) — Custom exception hierarchy
- **Transforms** (`lib/api_client/transforms.rb`) — Shared transform registry + Recipe data class
- **Profiling** (`lib/api_client/profiling.rb`) — StackProf integration (cpu/wall/allocations/auto-slow)
- **RegistryBase** (`lib/api_client/concerns/registry_base.rb`) — Shared memoized detection for registries
- **Poolable** (`lib/api_client/concerns/poolable.rb`) — Shared connection pooling (build_pool, with_pooled_connection)
- **NullPool** (`lib/api_client/concerns/poolable.rb`) — Pass-through pool when pooling disabled; same `.with` interface

### Optional

- **JWT** (`lib/api_client/jwt.rb`) — Module entry with lazy-loading and autoload
- **JWT::Token** (`lib/api_client/jwt/token.rb`) — RFC 8725 encode/decode
- **JWT::Authenticator** (`lib/api_client/jwt/authenticator.rb`) — Bearer token injection (headers or Faraday middleware)
- **JWT::Auditor** (`lib/api_client/jwt/auditor.rb`) — Algorithm/JWK/secret validation
- **JWT::KeyStore** (`lib/api_client/jwt/key_store.rb`) — Thread-safe key storage with 4-phase rotation
- **JWT::JwksClient** (`lib/api_client/jwt/jwks_client.rb`) — JWKS endpoint with TTL caching
- **Railtie** (`lib/api_client/railtie.rb`) — Rails integration (logger, notification subscription)
- **OpenTelemetryHeaders** (`lib/middlewares/faraday/open_telemetry_headers.rb`) — Faraday middleware for X-Request-Faraday-Start

## Data Flow

### Simple Request

```text
client.get('/users/1')
    │
    ▼
Base#get → with_circuit
    │                    │
    │ (Stoplight)        │ (no Stoplight)
    │ state check        │ NullCircuit#run → yield
    ▼                    ▼
Connection#get (Faraday)
    │
    ├─► Hooks.instrument(:request_start)
    ├─► Faraday middleware stack
    ├─► Hooks.instrument(:request_complete)
    │
    ▼
Faraday::Response
```

### Batch Request

```text
client.batch([{method: :get, path: '/users/1'}, ...])
    │
    ▼
Base#batch → with_circuit
    │
    ▼
Orchestrators::Batch#execute
    │
    ▼
Backend::Registry.detect → best available backend
    │
    ├─► TyphoeusAdapter → Typhoeus::Hydra
    ├─► AsyncAdapter    → Async fibers
    ├─► ConcurrentAdapter → thread pool
    └─► Sequential fallback
    │
    ▼
Array<Faraday::Response>
```

### RequestFlow (Streaming Fan-Out)

```text
client.request_flow
  .fetch(:get, '/users/123')
  .then { |r| JSON.parse(r.body)['post_ids'] }
  .fan_out { |id| { method: :get, path: "/posts/#{id}" } }
  .parallel_map(recipe: Recipe.default) { |data| transform(data) }
  .collect
    │
    ▼
RequestFlow#collect (executes steps sequentially)
    │
    ├─► fetch → Connection#get → Faraday::Response
    │
    ├─► then → transform block → Array<post_ids>
    │
    ├─► fan_out (on_ready: :stream)
    │     └─► FanOutExecutor
    │           • Async semaphore (max_inflight: nproc × √2)
    │           • Per-request retry with exponential backoff
    │           • FailureStrategy (fail_fast/skip/collect/callback)
    │           → Array<Faraday::Response>
    │
    └─► parallel_map → Processing::Registry.detect
          └─► RactorProcessor / AsyncProcessor / ConcurrentProcessor
                • Recipe (extract: :body, transform: :json)
                • ErrorStrategy (fail_fast/collect/skip/replace)
                → Array<Hash>
```

## Configuration Hierarchy

```text
ApiClient.configuration (global defaults, mutex-protected)
    │
    ▼
ApiClient::Base.new(url:, **overrides, &block)
    │
    ▼
config.merge(overrides) → effective config
    │
    ├─► RetryConfig     (max, interval, backoff_factor, exceptions)
    ├─► CircuitConfig   (threshold, cool_off, window_size, redis_pool)
    ├─► JwtConfig       (algorithm, issuer, audience, key)
    ├─► ProcessorConfig (ractor/async/concurrent pool sizes)
    └─► PoolConfig      (size, timeout, enabled)
```

## Error Hierarchy

```text
StandardError
└── ApiClient::Error
    ├── CircuitOpenError              # Circuit breaker tripped
    ├── TimeoutError                  # Request timeout (open/read/write)
    ├── ConfigurationError            # Invalid config
    ├── NoAdapterError                # No concurrency adapter available
    ├── ProcessingError               # Base for parallel failures (partial results)
    │   ├── RactorProcessingError     # Ractor failure
    │   ├── AsyncProcessingError      # AsyncProcessor failure
    │   ├── ConcurrentProcessingError # ConcurrentProcessor failure
    │   └── FanOutError               # Streaming fan-out failure
    └── Jwt::Error                    # Base for JWT errors
        ├── JwtUnavailableError       # jwt gem missing or too old
        ├── InvalidAlgorithmError     # Forbidden algorithm (none, HS*)
        ├── InvalidJwkError           # Bad JWK structure
        ├── WeakSecretError           # HMAC secret too short
        ├── KeyNotFoundError          # Key not in JWKS/KeyStore
        ├── JwksFetchError            # JWKS endpoint fetch failed
        └── TokenVerificationError    # Token decode/verify failed
```

## Dependencies

### Runtime (required)

- `activesupport` — Notifications, core extensions
- `zeitwerk` — Autoloading
- `connection_pool` — Thread-safe connection pooling
- `faraday` — HTTP client
- `faraday-retry` — Retry middleware
- `nxt_registry` — RequestFlow step registry
- `stoplight` — Circuit breaker
- `stackprof` — Sampling profiler

### Optional (loaded if available)

- `typhoeus` + `faraday-typhoeus` — HTTP/2 backend (Hydra concurrency), Faraday adapter
- `async` + `async-http` — Fiber-based backend (Ruby 3+)
- `async-container` — Fork-based processor
- `concurrent-ruby` — Thread pool backend/processor
- `jwt` — JWT support

## Further Reading

- [onboarding.md](onboarding.md) — Quick start guide
- [ecosystem.md](ecosystem.md) — Ruby HTTP client comparison
- [circuit-breaker.md](circuit-breaker.md) — Circuit breaker pattern and Stoplight vs NullCircuit
- [auth/jwt.md](auth/jwt.md) — JWT authentication
- [onboarding.http.typhoeus.md](onboarding/onboarding.http.typhoeus.md) — Typhoeus backend
- [onboarding.processing.ractor.md](onboarding/onboarding.processing.ractor.md) — Ractor processing (CPU-bound)
