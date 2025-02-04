---
title: "Orchestrators"
audience_chain:
  - "developer"
  - "maintainer"
parent: "../onboarding.md"
semantic_version: "1.0"
last_updated_at: "2026-02-06"
---
# Orchestrators

Request dispatch coordination layer.

## Architecture

```
client.batch → Batch → Registry.detect → Adapter.execute → Array<Response>
```

## Types

| Orchestrator | Purpose                         |
|--------------|---------------------------------|
| Batch        | Auto-detect adapter, concurrent |
| Sequential   | One-at-a-time dispatch          |

## Batch Orchestrator

```ruby
batch = ApiClient::Orchestrators::Batch.new(config)
responses = batch.execute([
  { method: :get, path: '/users/1' },
  { method: :get, path: '/users/2' }
])
batch.adapter_name  # => :typhoeus

# Force adapter
batch = ApiClient::Orchestrators::Batch.new(config, adapter: :async)
```

## Sequential Orchestrator

```ruby
sequential = ApiClient::Orchestrators::Sequential.new(connection)
responses = sequential.execute(requests)
```

## Adapter Registry

```ruby
Adapters::Registry.detect             # => :typhoeus
Adapters::Registry.available?(:async) # => true
Adapters::Registry.available_adapters # => [:typhoeus, :async, :ractor, :concurrent]
Adapters::Registry.resolve(:typhoeus) # => TyphoeusAdapter
```

## Guides

[batch](onboarding.orchestrators.batch.md) |
[sequential](onboarding.orchestrators.sequential.md)
