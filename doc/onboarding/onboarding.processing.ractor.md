---
title: "Ractor Processor"
audience_chain:
  - "developer"
  - "maintainer"
parent: "onboarding.processing.md"
semantic_version: "1.0"
last_updated_at: "2026-02-06"
---
# Experimental Ractor Processor

True CPU parallelism through Ruby's experimental Ractor API (Ruby 4.0+ for
`Ractor::Port`). Ractor is not selected by automatic processor detection.
See [onboarding.processing.md](onboarding.processing.md).

## Installation

No additional gems (Ruby 3.0+).

## Features

| Feature      | Value                      |
|--------------|----------------------------|
| Parallelism  | True (bypasses GVL)        |
| Memory model | Isolated, explicit sharing |
| Use case     | CPU-bound transforms       |
| Ruby         | 4.0+ (experimental)        |
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
ApiClient::Processing::Registry.available?(:ractor) # => true when Ractor::Port exists
```

Use `RequestFlow#parallel_map` or `RactorProcessor` explicitly to opt in. The
default suite excludes the experimental Ractor examples; run them with
`bundle exec rspec --tag experimental_ractor` to exercise the feature and see
Ruby's experimental API warnings. On Ruby versions without `Ractor::Port`, the
tagged examples are skipped.
