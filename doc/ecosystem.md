# Ruby HTTP Client Ecosystem

## Landscape

Libraries (opinionatedly) ranked by resilience, concurrency,
security, maintainability, and ecosystem health:

1. **api-client** — this gem (see below)
2. **httpx** — HTTP/2 native, plugin architecture
3. **typhoeus** — libcurl parallel via Hydra
4. **async-http** — fiber-based, Async runtime
5. **faraday** — middleware stack, adapter-agnostic
6. **httparty** — DSL wrapper over Net::HTTP
7. **net-http** — stdlib, zero dependencies
8. **rest-client** — abandoned, CVE-2019-15224

## What Each Library Does

### api-client (this gem)

Orchestration and resilience layer on Faraday. Auto-detects
the best concurrency backend at boot — fibers (Async),
threads (Concurrent), or OS-level multiplexing via
Typhoeus/libcurl Hydra (HTTP/2). Thread-safe throughout.

Pipeline chaining (`fetch → then → fan_out → collect`)
with backpressure and retry. Circuit breaking via Stoplight
with four error strategies. Three processing backends:
Ractor (isolated CPU parallelism), Async (fork isolation),
Concurrent (thread pool). JWT with JWKS caching and
4-phase key rotation. SSRF prevention via UriPolicy.
30+ lifecycle hooks. StackProf auto-slow detection.
Connection pooling. Raw Faraday responses — no wrapping.

Good choice when: you need resilient concurrent HTTP
with orchestration, not assembly.

### httpx (~8M downloads)

Modern HTTP client with native HTTP/2, connection
coalescing, and built-in plugin system. Persistent
connections by default. Plugins for circuit breaking,
retries, rate limiting, WebDAV, gRPC. Thread-safe.
No external dependencies for core.

Good choice when: you want HTTP/2 native, plugin
architecture, and don't need Faraday middleware
compatibility.

### typhoeus (~95M downloads)

Ruby bindings for libcurl. Hydra provides true parallel
HTTP via libcurl's multi interface — OS-level multiplexing,
not threads or fibers. HTTP/2 support. Fastest raw
throughput for batch requests.

Good choice when: you need maximum parallel HTTP
throughput and can accept the libcurl dependency.

### async-http (~12M downloads)

Fiber-based HTTP client built on the Async framework.
Non-blocking I/O without threads. Connection pooling
and HTTP/2 via the Async event loop. Requires the
Async runtime — not a drop-in for synchronous code.

Good choice when: you're already in an Async context
(Falcon server, Async tasks) and want native
non-blocking HTTP.

### faraday (~85M downloads)

The ecosystem standard. Middleware stack architecture —
request/response processing via composable layers.
Adapter-agnostic (Net::HTTP, Typhoeus, Async, etc.).
No built-in concurrency, circuit breaking, or pipeline
orchestration. You build those yourself.

Good choice when: you want full control over the
middleware stack and don't need concurrency orchestration.

### httparty (~290M downloads)

DSL-driven HTTP client wrapping Net::HTTP. Class-level
configuration with `base_uri`, `headers`, `format`.
Simple and readable for basic API consumption. No
middleware, no concurrency, no connection pooling.

Good choice when: you need a quick script or simple
API wrapper with minimal ceremony.

### net-http (stdlib)

Ruby's built-in HTTP client. No dependencies. Verbose
API, manual connection management, no middleware.
Every other library in this list wraps or replaces it.

Good choice when: you can't add gems (restricted
environments, bootstrapping).

### rest-client (~200M downloads)

Thin wrapper around Net::HTTP. Automatic redirect
following, multipart uploads. Effectively unmaintained
since 2019. CVE-2019-15224 (remote code execution via
crafted headers).

Avoid for new projects. Migrate to Faraday or HTTParty.

## api-client vs the Field

| Concern                | Faraday   | api-client                            |
|------------------------|-----------|---------------------------------------|
| Middleware stack       | ✓         | ✓ (inherits)                          |
| Connection pooling     | manual    | built-in (ConnectionPool)             |
| Adapter selection      | manual    | auto-detected                         |
| Batch requests         | —         | Orchestrator (Sequential/Batch)       |
| Pipeline chaining      | —         | RequestFlow (fetch → fan_out → collect)|
| Circuit breaker        | —         | Stoplight integration                 |
| Error strategies       | —         | fail_fast, collect, skip, replace     |
| Processing backends    | —         | Ractor, Async, Concurrent             |
| JWT authentication     | —         | 4-phase key rotation                  |
| SSRF prevention        | —         | UriPolicy with blocklist              |
| Lifecycle hooks        | —         | ActiveSupport::Notifications (30+)    |
| Profiling              | —         | StackProf auto-slow detection         |

Faraday is the HTTP transport. api-client is the
orchestration and resilience layer on top.

## Adapter Auto-Detection

api-client probes for available gems at boot and
selects the best concurrency backend:

```
Typhoeus (libcurl Hydra) → Async (fibers) → Concurrent (threads)
```

Override with `config.adapter = :async` if needed.
Falls back to sequential execution if no concurrency
gem is installed.

## Migration

### From raw Faraday

```ruby
# Before
conn = Faraday.new(url: "https://api.example.com") do |f|
  f.request :retry, max: 3
  f.adapter :net_http
end
response = conn.get("/users/1")

# After
client = ApiClient.new(url: "https://api.example.com")
response = client.get("/users/1")
```

Response objects are raw Faraday responses — no wrapping,
no surprises.

### From HTTParty

```ruby
# Before
class UserApi
  include HTTParty
  base_uri "https://api.example.com"
end
response = UserApi.get("/users/1")

# After
client = ApiClient.new(url: "https://api.example.com")
response = client.get("/users/1")
```

## See Also

- [../README.md](../README.md) — Quick start and install
- [architecture.md](architecture.md) — System diagrams and component map
- [circuit-breaker.md](circuit-breaker.md) — Resilience pattern details
