---
title: "Concurrent-Ruby Adapter"
audience_chain:
  - "developer"
  - "maintainer"
parent: "onboarding.http.md"
semantic_version: "1.1"
last_updated_at: "2026-02-07"
---
# Concurrent-Ruby Adapter

Thread pool concurrency. See [onboarding.http.md](onboarding.http.md).

## Installation

```ruby
gem 'concurrent-ruby'
```

## Features

| Feature     | Value              |
|-------------|--------------------|
| Concurrency | Thread pool        |
| Memory      | ~1MB per thread    |
| Compat      | All Ruby versions  |
| HTTP client | Faraday (net_http) |

## How It Works

Faraday connections are pooled via `Concerns::Poolable` (ConnectionPool).
Each thread checks out a connection from the pool, executes the request,
and checks it back in — no shared mutable state between threads.

```ruby
futures = requests.map do |request|
  Concurrent::Future.execute { execute_request(request) }
end
futures.map(&:value)
```

`execute_request` calls `with_pooled_connection` internally, so each
future gets its own Faraday instance from the pool.

## When to Use

- Moderate concurrency needs
- Typhoeus/Async unavailable
- Thread-safe environment required
- Simpler dependency tree preferred
