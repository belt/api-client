---
title: "Sequential Orchestrator"
audience_chain:
  - "developer"
  - "maintainer"
parent: "onboarding.orchestrators.md"
semantic_version: "1.0"
last_updated_at: "2026-02-06"
---
# Sequential Orchestrator

One-at-a-time request dispatcher.

See [onboarding.orchestrators.md](onboarding.orchestrators.md) for shared concepts.

## Features

| Feature      | Value                       |
|------------- |-----------------------------|
| Concurrency  | None                        |
| Dependencies | None                        |
| Use case     | Fallback, rate-limited APIs |

## Usage

```ruby
# Via Batch (fallback when no concurrent adapters)
batch = ApiClient::Orchestrators::Batch.new(config)

# Direct
sequential = ApiClient::Orchestrators::Sequential.new(connection)
responses = sequential.execute(requests)
```

## Implementation

```ruby
requests.map { |req| Orchestrators.execute_request(connection, req) }
```

## Instrumentation

Events with `adapter: :sequential`:

```ruby
ActiveSupport::Notifications.subscribe('api_client.batch.complete') do |*args|
  event = ActiveSupport::Notifications::Event.new(*args)
  event.payload[:adapter]  # => :sequential
end
```
