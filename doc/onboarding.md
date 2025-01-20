---
title: "ApiClient Onboarding Guide"
audience_chain:
  - "developer"
  - "maintainer"
semantic_version: "1.0"
last_updated_at: "2026-02-06"
---
# ApiClient Onboarding Guide

HTTP client with concurrent requests, circuit breaker, request flow workflows,
streaming fan-out, and JWT authentication built on Faraday.

## Why ApiClient?

| Need                   | Faraday | Faraday + effort    | ApiClient          |
|------------------------|---------|---------------------|--------------------|
| Sequential HTTP        | ✓       | ✓                   | ✓                  |
| Batch HTTP             | ✗       | typhoeus hydra      | ✓ (auto-detected)  |
| HTTP/2                 | ✗       | typhoeus            | ✓ (via typhoeus)   |
| Retry with backoff     | ✗       | faraday-retry       | ✓ (integrated)     |
| Connection pooling     | ✗       | connection_pool     | ✓ (integrated)     |
| Persistent conns       | ✗       | net_http_persistent | ✓ (via adapter)    |
| sequential-to-parallel | ✗       | ✗                   | ✓                  |
| Circuit breaker        | ✗       | faulty gem          | ✓ (Stoplight)      |
| Production profiling   | ✗       | ✗                   | ✓ (StackProf)      |
| Adaptive profiling     | ✗       | ✗                   | ✓ (on_slow-query)  |
| JWT/JWKS auth          | ✗       | ✗                   | ✓ (jwt + RFC 8725) |
| Concurrent Parsing     | ✗       | async/thread/ractor | ✓ (auto-detected)  |
| AS::Notifications      | ✗       | ✗                   | ✓ (active-support) |
| OpenTelemetry support  | ✗       | custom middleware   | ✓ (integrated)     |

### Bring your own gems

If it's available, ApiClient has strong opinions and will use them:

- Ractor (ruby-3.4+)
- Async/Async::HTTP
- Concurrent::Ruby
- Typhoeus/Faraday::Typhoeus
- Jwt

## Installation

```ruby
# Gemfile
gem 'api-client'

# Optional adapters (auto-detected)
gem 'faraday-typhoeus'  # HTTP/2, fastest concurrent
gem 'async-http'        # Fiber-based concurrency
gem 'concurrent-ruby'   # Thread pool based

# Optional profiling
gem 'rack-mini-profiler'
```

## Quick Start

```ruby
require 'api_client'

# Module-level (one-off requests)
response = ApiClient.get('https://api.example.com/users')

# Instance-level (recommended)
client = ApiClient.new(url: 'https://api.example.com')
response = client.get('/users/1')
response = client.post('/users', { name: 'Bob' })

# With params and headers
client.get('/users', { page: 1 }, { 'X-Custom' => 'value' })
```

## Configuration

```ruby
ApiClient.configure do |config|
  config.service_uri = 'https://api.example.com'
  config.open_timeout = 5
  config.read_timeout = 30
  config.write_timeout = 10

  config.default_headers = {
    'Accept' => 'application/json',
    'Content-Type' => 'application/json'
  }

  # Retry (delegates to faraday-retry)
  config.retry do |conf|
    conf.max = 3
    conf.interval = 0.5
    conf.backoff_factor = 2
    conf.retry_statuses = [429, 500, 502, 503, 504]
  end

  # Circuit breaker (delegates to Stoplight)
  config.circuit do |conf|
    conf.threshold = 5
    conf.cool_off = 30
  end

  # Connection pool (Faraday connections)
  config.pool do |conf|
    conf.size = 10       # max pooled connections (default: nproc)
    conf.timeout = 5     # checkout timeout in seconds
    conf.enabled = true  # false → NullPool pass-through
  end

  config.on_error = :raise  # :raise | :return | :log_and_return
  config.log_requests = true
  config.log_bodies = false
end
```

## Batch Requests

Auto-detects best adapter: Typhoeus > Async > Ractor > Concurrent-ruby > Sequential

```ruby
responses = client.batch([
  { method: :get, path: '/users/1' },
  { method: :get, path: '/users/2' },
  { method: :get, path: '/users/3' }
])

# Check adapter
client.batch_adapter  # => :typhoeus
```

**HTTP guide**: [onboarding.http.md](onboarding/onboarding.http.md) — Shared concepts

**Backend variants**: [typhoeus](onboarding/onboarding.http.typhoeus.md) |
[async](onboarding/onboarding.http.async.md) |
[concurrent](onboarding/onboarding.http.concurrent.md) |
[sequential](onboarding/onboarding.http.sequential.md)

**Orchestrators**: [onboarding.orchestrators.md](onboarding/onboarding.orchestrators.md) — Request dispatch

## Processing Strategies

**Processing guide**: [onboarding.processing.md](onboarding/onboarding.processing.md) — Shared concepts

**Processor variants** (auto-detected):

- [onboarding.processing.ractor.md](onboarding/onboarding.processing.ractor.md) — Ractor (Ruby 3.0+)
- [onboarding.processing.async.md](onboarding/onboarding.processing.async.md) — Fork-based (Unix)
- [onboarding.processing.concurrent.md](onboarding/onboarding.processing.concurrent.md) — Thread-based (all platforms)

**Workflow**: [onboarding.processing.request_flow.md](onboarding/onboarding.processing.request_flow.md) — Sequential-to-parallel chains

### RequestFlow Example

```ruby
# Streaming fan-out (default) — responses processed as they arrive
posts = client.request_flow
  .fetch(:get, '/users/123')
  .then { |r| JSON.parse(r.body)['post_ids'] }
  .fan_out(
    on_fail: :skip,           # Skip failed requests
    timeout_ms: 5000,         # 5s per request
    retries: { max: 2 }       # Retry twice with exponential backoff
  ) { |id| { method: :get, path: "/posts/#{id}" } }
  .parallel_map
  .collect
```

### RequestFlow Steps

| Step             | Purpose                              |
|------------------|--------------------------------------|
| `fetch`          | Sequential HTTP request              |
| `then`           | Transform current result             |
| `fan_out`        | Concurrent requests from array       |
| `filter`         | Filter array items                   |
| `map`            | Transform each item                  |
| `parallel_map`   | Ractor CPU parallelism               |
| `async_map`      | Fork CPU parallelism                 |
| `concurrent_map` | Thread CPU parallelism               |
| `process`        | Auto-detect best processor           |
| `collect`        | Execute flow, return result          |

## Circuit Breaker

```ruby
# Automatic protection
response = client.get('/health')

# Check state
client.circuit_open?  # => true if failing fast

# Manual reset
client.reset_circuit!
```

| State              | Behavior                            |
|--------------------|-------------------------------------|
| GREEN (closed)     | Normal operation                    |
| RED (open)         | Fail fast, raise `CircuitOpenError` |
| YELLOW (half-open) | Probe with single request           |

## JWT Authentication

See [auth/jwt.md](auth/jwt.md) for full documentation.

```ruby
require 'api_client/jwt'

# Encode
token = ApiClient::Jwt::Token.new(algorithm: 'RS256', key: private_key)
jwt = token.encode({ sub: 'user123' }, expires_in: 900)

# Authenticate requests
auth = ApiClient::Jwt::Authenticator.new(token_provider: jwt)
client = ApiClient.new(default_headers: auth.headers)
```

## Observability

All operations emit AS::Notifications events for monitoring and debugging.

```ruby
# Request events
ActiveSupport::Notifications.subscribe('api_client.request.complete') do |*args|
  event = ActiveSupport::Notifications::Event.new(*args)
  puts "#{event.payload[:method]} #{event.payload[:url]} - #{event.payload[:status]}"
end

# Batch events (adapters/orchestrators)
ActiveSupport::Notifications.subscribe('api_client.batch.complete') do |*args|
  event = ActiveSupport::Notifications::Event.new(*args)
  puts "Batch: #{event.payload[:count]} requests via #{event.payload[:adapter]} in #{event.payload[:duration]}s"
end

# RequestFlow events
ActiveSupport::Notifications.subscribe('api_client.request_flow.complete') do |*args|
  event = ActiveSupport::Notifications::Event.new(*args)
  puts "RequestFlow: #{event.payload[:step_count]} steps in #{event.payload[:duration]}s"
end

# Circuit events
ActiveSupport::Notifications.subscribe('api_client.circuit.open') do |*args|
  event = ActiveSupport::Notifications::Event.new(*args)
  PagerDuty.alert("Circuit open: #{event.payload[:service]}")
end

# Fan-out events (streaming)
ActiveSupport::Notifications.subscribe('api_client.fan_out.complete') do |*args|
  event = ActiveSupport::Notifications::Event.new(*args)
  puts "Fan-out: #{event.payload[:input_count]} requests, #{event.payload[:output_count]} results"
end

# Custom hooks via configuration
ApiClient.configure do |config|
  config.on(:request_complete) { |payload| StatsD.increment('api.request') }
  config.on(:batch_complete) { |payload| StatsD.timing('api.batch', payload[:duration]) }
  config.on(:circuit_open) { |payload| PagerDuty.alert(payload[:service]) }
end
```

### Event Lifecycle

#### Single Request

```ruby
client.get('/users/1')
```

```text
┌─────────────────────────────────────────────────────────────────┐
│ [Circuit check] ──── circuit.rejected (if open) ───► ERROR      │
│     ↓                                                           │
│ request.start                                                   │
│     ↓                                                           │
│ [HTTP via Faraday]                                              │
│     ↓                                                           │
│ request.complete ─── request.slow (if > threshold)              │
│     │                     ↓                                     │
│     │               profile.captured (if auto-profile on)       │
│     ↓                                                           │
│ Faraday::Response                                               │
└─────────────────────────────────────────────────────────────────┘
```

### Batch Request

```ruby
client.batch([...])
```

```text
┌─────────────────────────────────────────────────────────────────┐
│ [Circuit check] ──── circuit.rejected (if open) ───► ERROR      │
│     ↓                                                           │
│ batch.start (adapter: :typhoeus, count: N)                      │
│     ↓                                                           │
│ [Adapter executes N requests concurrently]                      │
│ (no per-request events — adapter handles internally)            │
│     ↓                                                           │
│ batch.complete (duration, success_count)                        │
│     │                                                           │
│     └─── batch.slow (if duration_ms > batch_slow_threshold_ms)  │
│     ↓                                                           │
│ Array<Faraday::Response>                                        │
└─────────────────────────────────────────────────────────────────┘
```

### RequestFlow

```ruby
 client.request_flow.fetch(...).fan_out(...).parallel_map(...).collect
```

```text
┌─────────────────────────────────────────────────────────────────┐
│ request_flow.start (step_count: 3)                              │
│     ↓                                                           │
│ ┌─ Step 0: fetch ─────────────────────────────────────────────┐ │
│ │  request.start → request.complete (single request)          │ │
│ │  request_flow.step (step_index: 0, step_type: :fetch)       │ │
│ └─────────────────────────────────────────────────────────────┘ │
│     ↓                                                           │
│ ┌─ Step 1: fan_out ───────────────────────────────────────────┐ │
│ │  fan_out.start → fan_out.complete (streaming or batch)      │ │
│ │  fan_out.retry (per-request retries, if configured)         │ │
│ │  fan_out.error (per-request failures)                       │ │
│ │  request_flow.step (step_index: 1, step_type: :fan_out)     │ │
│ └─────────────────────────────────────────────────────────────┘ │
│     ↓                                                           │
│ ┌─ Step 2: process (auto-detect) ─────────────────────────────┐ │
│ │  Processing::Registry.detect → best available processor     │ │
│ │  (ractor.* | async_processor.* | concurrent_processor.*)    │ │
│ │  request_flow.step (step_index: 2, step_type: :process)     │ │
│ └─────────────────────────────────────────────────────────────┘ │
│     ↓                                                           │
│ request_flow.complete (duration)                                │
│     ↓                                                           │
│ Array<Hash> (parsed responses)                                  │
└─────────────────────────────────────────────────────────────────┘
```

### Circuit State Transitions (background)

```text
┌─────────────────────────────────────────────────────────────────┐
│ GREEN ──[failures > threshold]──► circuit.open ──► RED          │
│   ↑                                                  ↓          │
│   └──── circuit.close ◄── circuit.half_open ◄── [cool_off]      │
└─────────────────────────────────────────────────────────────────┘
```

## Profiling

Production-safe profiling via StackProf (sampling profiler).

```ruby
# Manual CPU profiling
dump_path = ApiClient::Profiling.cpu do
  client.batch(large_request_set)
end
# => "tmp/profiles/stackprof-cpu-20260204-123456.dump"

# Generate flamegraph
ApiClient::Profiling.flamegraph(dump_path)
# => "tmp/profiles/stackprof-cpu-20260204-123456.html"

# Auto-profile slow operations
result = ApiClient::Profiling.profile_if_slow(threshold_ms: 500) do
  client.request_flow.fetch(:get, '/slow').collect
end

# Enable auto-profiling for all slow requests
ApiClient::Profiling.auto_profile_slow_requests!(threshold_ms: 999)

# Rack middleware
use ApiClient::Profiling::Middleware,
    enabled: ENV['PROFILE'] == 'true',
    auto_slow: true,
    slow_threshold_ms: 500
```

## Error Handling

```ruby
begin
  response = client.get('/users/1')
rescue ApiClient::CircuitOpenError => e
  use_cached_response
rescue ApiClient::TimeoutError => e
  logger.error "Timeout: #{e.timeout_type}"
rescue ApiClient::RactorProcessingError => e
  use_partial_results(e.partial_results)
rescue Faraday::Error => e
  logger.error "HTTP error: #{e.message}"
end
```

## Use Cases

### Microservice Client

```ruby
class UserServiceClient < ApiClient::Base
  def initialize
    super(
      url: ENV['USER_SERVICE_URL'],
      retry: { max: 3 },
      circuit: { threshold: 5, cool_off: 30 }
    )
  end

  def find(id) = get("/users/#{id}").then { JSON.parse(_1.body) }

  def find_many(ids)
    batch(ids.map { |id| { method: :get, path: "/users/#{id}" } })
      .map { JSON.parse(_1.body) }
  end
end
```

### Health Check Aggregator

```ruby
def check_dependencies
  client = ApiClient.new(read_timeout: 2)
  services = %w[users orders payments]

  responses = client.batch(
    services.map { |s| { method: :get, path: "https://#{s}.internal/health" } }
  )

  services.zip(responses).to_h { |s, r| [s, r.status == 200 ? :healthy : :unhealthy] }
end
```

## Migration from Faraday

```ruby
# Before (Faraday)
conn = Faraday.new(url: 'https://api.example.com') do |f|
  f.request :json
  f.request :retry, max: 3
  f.response :json
  f.adapter :net_http
end
response = conn.get('/users/1')

# After (ApiClient)
client = ApiClient.new(url: 'https://api.example.com', retry: { max: 3 })
response = client.get('/users/1')

# Same response object (Faraday::Response)
response.status  # => 200
response.body    # => '{"id": 1, ...}'
```

## Environment Variables

```bash
RUBY_YJIT_ENABLE=1
RUBYOPT='--enable=frozen-string-literal'
API_CLIENT_LOG_REQUESTS=true
API_CLIENT_LOG_BODIES=false
```

## Further Reading

- [architecture.md](architecture.md) — System architecture and design
- [auth/jwt.md](auth/jwt.md) — JWT/JWKS documentation
- [examples/README.md](../lib/api_client/examples/README.md) — Canonical RequestFlow examples (4×4 adapter × processor matrix)
- [test_server/README.md](../spec/support/test_server/README.md) — Integration test server (Falcon-based, real TCP)
- [Faraday](https://lostisland.github.io/faraday/)
- [Stoplight](https://github.com/bolshakov/stoplight)
- [StackProf](https://github.com/tmm1/stackprof)
