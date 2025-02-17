---
title: "Circuit Breaker"
audience_chain:
  - "developer"
  - "maintainer"
semantic_version: "1.1"
last_updated_at: "2026-02-07"
---

# Circuit Breaker

## The Pattern

A circuit breaker sits between your code and a downstream service. It
monitors failures and, after a threshold is crossed, stops sending
requests — failing immediately instead of waiting for timeouts. This
prevents a sick service from dragging your application down with it.

Three states:

```text
closed (green)     → requests flow normally, failures are counted
open (red)         → requests rejected immediately (fail-fast)
half-open (yellow) → one probe request allowed after cool-off to test recovery
```

Lifecycle:

```text
         failures >= threshold
closed ──────────────────────────► open
  ▲                                  │
  │          cool-off expires        ▼
  │                              half-open
  │    probe succeeds                │
  └──────────────────────────────────┘
         probe fails → back to open
```

## How api-client Uses It

Every HTTP call in `Base` flows through `with_circuit`:

```ruby
# Base#get, #post, etc.
def get(path, ...)
  with_circuit { connection.get(path, ...) }
end

def with_circuit(&block)
  circuit.run(&block)
end
```

`Circuit.new` is a factory — it returns a `Circuit` (Stoplight-backed) or
a `NullCircuit` (pass-through) depending on whether the gem is installed:

```ruby
def self.new(name, config = ...)
  return NullCircuit.new(name, config) unless defined?(::Stoplight)
  # ... build real circuit
end
```

Circuits are keyed per-host (`api_client:{hostname}`), so each downstream
service has independent failure tracking.

## With Stoplight (Circuit)

Stoplight manages the state machine. Configuration via `CircuitConfig`:

| Setting          | Default | Purpose                                   |
|------------------|---------|-------------------------------------------|
| `threshold`      | 5       | Failures before opening                   |
| `cool_off`       | 30s     | Seconds before half-open probe            |
| `window_size`    | nil     | Sliding window (seconds); nil = count all |
| `tracked_errors` | nil     | Error classes to count; nil = all errors  |
| `data_store`     | :memory | `:memory` or `:redis` for shared state    |
| `redis_client`   | nil     | Raw Redis client for Stoplight data store |
| `redis_pool`     | nil     | ConnectionPool of Redis (preferred)       |

Features:

- Fail-fast — open circuit raises `CircuitOpenError` (or runs fallback)
- Fallbacks — `circuit.with_fallback { cached_response }`
- Error handlers — `circuit.on_error { |e| notify_ops(e) }`
- State transitions instrumented via `Hooks`:
  `:circuit_open`, `:circuit_half_open`, `:circuit_close`, `:circuit_rejected`
- Thread-safe via `Mutex` + Stoplight internals
- Shared state across processes when backed by Redis

## Without Stoplight (NullCircuit)

Same interface, no protection:

| Method            | Returns                   |
|-------------------|---------------------------|
| `run { block }`   | Yields directly           |
| `open?`           | `false`                   |
| `state`           | `"green"`                 |
| `failure_count`   | `0`                       |
| `recent_failures` | `[]`                      |
| `with_fallback`   | `self` (no-op)            |
| `on_error`        | `self` (no-op)            |
| `metrics`         | `{ enabled: false, ... }` |

Every request hits the network regardless of downstream health. There is
no threshold, no cool-off, no recovery probing. Fallback blocks are
silently discarded.

## Comparison

| Capability                    | Circuit (Stoplight) | NullCircuit            |
|-------------------------------|---------------------|------------------------|
| Fail-fast on sick services    | Yes                 | No — waits for timeout |
| Cascading failure protection  | Stops hammering     | Keeps piling on        |
| Automatic recovery probing    | Half-open probe     | N/A                    |
| Fallback responses            | Executes block      | Silently discarded     |
| State transition events       | Instrumented        | None emitted           |
| Sliding failure window        | `window_size`       | N/A                    |
| Error scoping                 | `tracked_errors`    | N/A                    |
| Shared state (Redis)          | Supported           | N/A                    |
| Failure count / recent errors | Tracked             | Always 0 / empty       |

## Configuration

```ruby
ApiClient.configure do |config|
  config.circuit do |c|
    c.threshold = 5        # failures before open
    c.cool_off = 30        # seconds before half-open
    c.window_size = 60     # sliding window (nil = all time)
    c.track_only(Faraday::TimeoutError, Faraday::ConnectionFailed)
  end
end
```

### Redis-Backed State (Shared Across Processes)

```ruby
ApiClient.configure do |config|
  config.circuit do |c|
    c.data_store = :redis

    # Preferred: ConnectionPool wrapping Redis (thread-safe)
    c.redis_pool = ConnectionPool.new(size: 5, timeout: 3) { Redis.new }

    # Alternative: raw Redis client (not pooled)
    # c.redis_client = Redis.new
  end
end
```

`redis_pool` takes precedence over `redis_client` when both are set.

## See Also

- [architecture.md](architecture.md) — System overview
- `lib/api_client/circuit.rb` — Stoplight-backed implementation
- `lib/api_client/null_circuit.rb` — Pass-through implementation
- `lib/api_client/configuration.rb` — `CircuitConfig`
