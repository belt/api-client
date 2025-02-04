---
title: "Batch Orchestrator"
audience_chain:
  - "developer"
  - "maintainer"
parent: "onboarding.orchestrators.md"
semantic_version: "1.0"
last_updated_at: "2026-02-06"
---
# Batch Orchestrator

Auto-detecting concurrent request dispatcher.

See [onboarding.orchestrators.md](onboarding.orchestrators.md) for shared concepts.

## Features

| Feature           | Value                                      |
|-------------------|--------------------------------------------|
| Adapter detection | Typhoeus > Async > Ractor > Concurrent > Sequential |
| Adapter override  | `adapter:` option                          |
| Empty handling    | Returns `[]` immediately                   |

## Usage

```ruby
# Via client
responses = client.batch([
  { method: :get, path: '/users/1' },
  { method: :post, path: '/users', body: '{"name":"Bob"}' }
])

# Direct
batch = ApiClient::Orchestrators::Batch.new(config)
responses = batch.execute(requests)

# Force adapter
client.batch(requests, adapter: :async)
```

## Introspection

```ruby
batch.adapter_name  # => :typhoeus
batch.adapter       # => TyphoeusAdapter instance
```
