# api-client

HTTP client gem with concurrent execution, circuit breaker,
request flow pipelines, and JWT authentication. Built on Faraday.

## Why

| Need               | Faraday alone    | api-client                         |
|--------------------|------------------|------------------------------------|
| Sequential HTTP    | ✓                | ✓                                  |
| Batch/concurrent   | manual Typhoeus  | auto-detected                      |
| Circuit breaker    | manual Stoplight | built-in                           |
| Request pipelines  | —                | `fetch → then → fan_out → collect` |
| JWT auth           | manual           | 4-phase key rotation               |
| SSRF prevention    | —                | UriPolicy with blocklist           |

## Install

### ore

```sh
ore add api-client -github belt/api-client
ore add typhoeus faraday-typhoeus async async-http concurrent-ruby jwt fiddle
```

```sh
ore install
```

### Bundler

In `Gemfile` add:

```ruby
gem "api-client", github: "belt/api-client"
gem "typhoeus"                # optional: HTTP/2 adapter
gem "faraday-typhoeus"        # optional: Faraday integration for typhoeus
gem "async"                   # optional: fiber-based adapter
gem "async-http"              # optional: async HTTP transport
gem "concurrent-ruby"         # optional: thread pool adapter
gem "jwt"                     # optional: JWT authentication
gem "fiddle"                  # optional: native RSS measurement
```

```sh
bundle
```

## Quick start

See [doc/onboarding.md](doc/onboarding.md) for the full guide.

```ruby
client = ApiClient.new(url: "https://api.example.com")

# Simple
response = client.get("/users/1")

# Concurrent (auto-selects Typhoeus > Async > Concurrent)
responses = client.concurrent([
  { method: :get, path: "/users/1" },
  { method: :get, path: "/users/2" },
])

# Pipeline
posts = client.request_flow
  .fetch(:get, "/users/123")
  .then { |r| JSON.parse(r.body)["post_ids"] }
  .fan_out { |id| { method: :get, path: "/posts/#{id}" } }
  .collect
```

## Architecture

See [doc/architecture.md](doc/architecture.md) for full system diagrams,
data flow, and component responsibilities.

```text
ApiClient::Base
├── Connection (Faraday + middleware + pool)
├── Orchestrators
│   ├── Sequential
│   └── Batch (auto-detected backend)
├── Adapters
│   ├── Typhoeus (HTTP/2 via libcurl Hydra)
│   ├── Async (fiber-based)
│   └── Concurrent (thread pool)
├── Processing
│   ├── RactorProcessor (CPU parallelism)
│   ├── AsyncProcessor (fork isolation)
│   └── ConcurrentProcessor (thread pool)
├── RequestFlow (chained pipelines)
├── Streaming::FanOutExecutor (backpressure + retry)
├── Circuit (Stoplight integration)
├── JWT::Authenticator (Bearer injection)
└── Hooks (ActiveSupport::Notifications, 30+ events)
```

## Configuration

```ruby
ApiClient.configure do |c|
  c.service_uri  = "https://api.example.com"
  c.open_timeout = 5
  c.read_timeout = 30
  c.adapter      = :typhoeus  # or :async, :concurrent
  c.on_error     = :raise     # or :collect, :skip
end
```

## Adapters

Auto-detection priority: Typhoeus → Async → Concurrent.
Per-adapter guides in [doc/onboarding/](doc/onboarding/onboarding.http.md).

| Adapter    | Mechanism             | Best for                  |
|------------|-----------------------|---------------------------|
| Typhoeus   | libcurl Hydra, HTTP/2 | High-throughput I/O       |
| Async      | Ruby fibers           | Lightweight concurrency   |
| Concurrent | Thread pool           | CPU-bound post-processing |

## JWT

```ruby
authenticator = ApiClient::JWT::Authenticator.new(
  jwks_uri: "https://auth.example.com/.well-known/jwks.json",
  audience: "api.example.com",
)
client = ApiClient.new(url: "https://api.example.com") do |c|
  c.jwt_authenticator = authenticator
end
```

KeyStore supports 4-phase rotation: active → retiring → retired → revoked.
See [doc/auth/jwt.md](doc/auth/jwt.md) for full configuration and key management.

## Processing

| Processor  | Isolation                    | Use case             |
|------------|------------------------------|----------------------|
| Ractor     | Process-level (Ractor::Port) | CPU-bound transforms |
| Async      | Fork                         | Untrusted workloads  |
| Concurrent | Thread pool                  | I/O-bound fan-out    |

## Examples

16 canonical clients in `lib/api_client/examples/` covering
the 4×4 adapter × processor matrix. Each has a matching spec.

Run all: `bundle exec rake examples:metrics`
See [doc/example-metrics.md](doc/example-metrics.md) for benchmark data.

## Development

```sh
bundle install
bundle exec rspec
bundle exec rake quality  # rubycritic, reek, flay, flog

# Install pre-push hook (CI parity gate on main)
git config core.hooksPath .githooks
```

## Requirements

- Ruby ≥ 3.2
- Faraday ≥ 2.0
- ActiveSupport ≥ 6.0

### Optional

| Gem              | Enables                             |
|------------------|-------------------------------------|
| typhoeus         | HTTP/2 adapter via libcurl Hydra    |
| faraday-typhoeus | Faraday integration for typhoeus    |
| async, async-http| Fiber-based concurrent adapter      |
| concurrent-ruby  | Thread pool adapter                 |
| jwt              | JWT authentication and key rotation |
| fiddle           | Native RSS measurement via FFI      |

## License

Apache-2.0
