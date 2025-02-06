---
title: "Ractor Processor"
audience_chain:
  - "developer"
  - "maintainer"
parent: "onboarding.processing.md"
semantic_version: "1.0"
last_updated_at: "2026-02-06"
---
# Ractor Processor

True CPU parallelism (Ruby 3.0+). See [onboarding.processing.md](onboarding.processing.md).

## Installation

No additional gems (Ruby 3.0+).

## Features

| Feature      | Value                      |
|--------------|----------------------------|
| Parallelism  | True (bypasses GVL)        |
| Memory model | Isolated, explicit sharing |
| Use case     | CPU-bound transforms       |
| Ruby         | 3.0+ (experimental)        |
| Restrictions | Shareable data only        |

## When to Use

| Task          | Ractor? |
|---------------|---------|
| JSON parsing  | ✓       |
| Checksum/HMAC | ✓       |
| HTTP requests | ✗       |
| Database      | ✗       |

## Configuration

Settings live on `config.processor_config`:

```ruby
ApiClient.configure do |config|
  pc = config.processor_config
  pc.ractor_pool_size = 4
  pc.ractor_min_batch_size = 10
  pc.ractor_min_payload_size = 1024
end
```

## Pool Options

```ruby
RactorProcessor.new(pool: :global)                   # shared (default)
RactorProcessor.new(pool: :instance, pool_size: 8)   # isolated
RactorProcessor.new(pool: custom_pool)               # custom
```

## Availability

```ruby
ApiClient::Processing::RactorProcessor.available?  # => true on Ruby 3.0+
```
