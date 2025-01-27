---
title: "Typhoeus Adapter"
audience_chain:
  - "developer"
  - "maintainer"
parent: "onboarding.http.md"
semantic_version: "1.0"
last_updated_at: "2026-02-06"
---
# Typhoeus Adapter

HTTP/2 via libcurl Hydra. See [onboarding.http.md](onboarding.http.md).

## Installation

```ruby
gem 'typhoeus'
```

## Features

| Feature       | Value       |
|---------------|-------------|
| HTTP/2        | Native      |
| Pooling       | libcurl     |
| TCP keepalive | Enabled     |
| TCP nodelay   | Enabled     |
| Parallelism   | Hydra queue |

## Configuration

```ruby
ApiClient.configure do |config|
  config.read_timeout = 30  # per-request timeout
  config.open_timeout = 5   # per-request connecttimeout
end
```

## When to Use

- High-throughput concurrent requests
- HTTP/2 required
- Connection reuse important
- libcurl available
