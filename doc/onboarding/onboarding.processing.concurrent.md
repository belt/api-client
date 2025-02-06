---
title: "Concurrent Processor"
audience_chain:
  - "developer"
  - "maintainer"
parent: "onboarding.processing.md"
semantic_version: "1.0"
last_updated_at: "2026-02-06"
---
# Concurrent Processor

Thread-based CPU parallelism. See [onboarding.processing.md](onboarding.processing.md).

## Installation

```ruby
gem 'concurrent-ruby'
```

## Features

| Feature      | Value         |
|--------------|---------------|
| Parallelism  | Thread pool   |
| Memory model | Shared memory |
| Use case     | Mixed I/O+CPU |
| Platform     | All (+ JRuby) |
| Overhead     | Low           |

## When to Use

- JRuby/TruffleRuby (true parallelism)
- Mixed I/O and CPU workloads
- Lower latency (no fork overhead)
- Windows or platforms without fork
- Shared state between transforms

## Configuration

Settings live on `config.processor_config`:

```ruby
ApiClient.configure do |config|
  pc = config.processor_config
  pc.concurrent_processor_pool_size = 4
  pc.concurrent_processor_min_batch_size = 4
end
```

## Thread Safety

Uses thread-safe collections:

- `Concurrent::Array` for errors
- `Concurrent::Set` for error indices
- `Concurrent::FixedThreadPool` for execution

Transform blocks must be thread-safe if accessing shared state.

## Availability

```ruby
ApiClient::Processing::ConcurrentProcessor.available?
```
