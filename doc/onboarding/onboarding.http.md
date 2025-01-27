---
title: "HTTP Adapters"
audience_chain:
  - "developer"
  - "maintainer"
parent: "../onboarding.md"
semantic_version: "1.1"
last_updated_at: "2026-02-07"
---
# HTTP Adapters

Concurrent HTTP request adapter concepts.

## Adapter Selection

`Backend::Registry.detect` → Typhoeus > Async > Concurrent > Sequential

| Backend    | Concurrency     | Deps              | Best For                |
|------------|-----------------|-------------------|-------------------------|
| Typhoeus   | libcurl Hydra   | typhoeus          | HTTP/2, high throughput |
| Async      | Fibers          | async, async-http | Many conns, low memory  |
| Concurrent | Thread pool     | concurrent-ruby   | Moderate concurrency    |
| Sequential | None            | None              | Fallback, rate-limited  |

## Usage

```ruby
client = ApiClient.new(url: 'https://api.example.com')
responses = client.batch([
  { method: :get, path: '/users/1' },
  { method: :get, path: '/users/2' }
])

client.batch_adapter                        # => :typhoeus
client.batch(requests, adapter: :async)     # force adapter
```

## Request Hash

| Key        | Type   | Req | Description       |
|------------|--------|-----|-------------------|
| `:method`  | Symbol | ✓   | :get, :post, etc. |
| `:path`    | String | ✓   | Path or full URL  |
| `:params`  | Hash   |     | Query parameters  |
| `:headers` | Hash   |     | Request headers   |
| `:body`    | String |     | Request body      |

## Response Normalization

All adapters → `Faraday::Response`:

| Property  | Value            |
|-----------|------------------|
| `status`  | HTTP status code |
| `body`    | Response string  |
| `headers` | Headers hash     |

## Connection Pooling

`Connection` and `ConcurrentAdapter` pool Faraday instances via
`Concerns::Poolable` (ConnectionPool gem). Each request checks out a
connection, uses it, and checks it back in. Configure via `config.pool`:

```ruby
config.pool do |p|
  p.size = 10       # max pooled connections (default: nproc)
  p.timeout = 5     # checkout timeout in seconds
  p.enabled = true  # false → NullPool (single instance, no pooling)
end
```

## Error Handling

| Error              | Raised                      |
|--------------------|-----------------------------|
| Timeout            | `Faraday::TimeoutError`     |
| Connection refused | `Faraday::ConnectionFailed` |
| Network errors     | Error response object       |

## Instrumentation

`ActiveSupport::Notifications` events:

| Event                       | Payload                                           |
|-----------------------------|---------------------------------------------------|
| `api_client.batch.start`    | `adapter`, `count`                                |
| `api_client.batch.complete` | `adapter`, `count`, `duration`, `success_count`   |
| `api_client.batch.slow`     | `adapter`, `count`, `duration_ms`, `threshold_ms` |

## Backend Guides

[typhoeus](onboarding.http.typhoeus.md) |
[async](onboarding.http.async.md) |
[concurrent](onboarding.http.concurrent.md) |
[sequential](onboarding.http.sequential.md)
