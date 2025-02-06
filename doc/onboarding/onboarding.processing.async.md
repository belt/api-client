---
title: "Async Processor"
audience_chain:
  - "developer"
  - "maintainer"
parent: "onboarding.processing.md"
semantic_version: "1.0"
last_updated_at: "2026-02-06"
---
# Async Processor

Fork-based CPU parallelism. See [onboarding.processing.md](onboarding.processing.md).

## Installation

```ruby
gem 'async-container'
```

## Features

| Feature      | Value                |
|--------------|----------------------|
| Parallelism  | True (fork)          |
| Memory model | Copy-on-write        |
| Use case     | CPU-bound transforms |
| Platform     | Unix only            |
| Maturity     | Production-ready     |

## When to Use

- Production systems needing stability
- Data hard to make Ractor-shareable
- Coarser-grained parallelism
- Already using async ecosystem

## Configuration

Settings live on `config.processor_config`:

```ruby
ApiClient.configure do |config|
  pc = config.processor_config
  pc.async_pool_size = 4
  pc.async_min_batch_size = 4
  pc.async_min_payload_size = 4096
end
```

## Platform Support

| Platform | Supported |
|----------|-----------|
| Linux    | ✓         |
| macOS    | ✓         |
| Windows  | ✗         |
| JRuby    | ✗         |

## Availability

```ruby
Async::Container.fork?                              # => true on Unix
ApiClient::Processing::AsyncProcessor.available?
```

## Related Ecosystem

async | async-http | async-container | falcon
