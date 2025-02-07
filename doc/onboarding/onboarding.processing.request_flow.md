---
title: "RequestFlow Execution"
audience_chain:
  - "developer"
  - "maintainer"
parent: "onboarding.processing.md"
semantic_version: "1.0"
last_updated_at: "2026-02-06"
---
# RequestFlow Execution

Sequential-to-parallel workflow chains. See [onboarding.processing.md](onboarding.processing.md).

## Features

| Feature      | Value                            |
|--------------|----------------------------------|
| Pattern      | fetch → transform → fan-out      |
| Concurrency  | Via adapter (auto-detected)      |
| CPU parallel | Via processor (auto-detected)    |
| Streaming    | Process responses as they arrive |

## Basic Usage

```ruby
posts = client.request_flow
  .fetch(:get, '/users/123')
  .then { |response| JSON.parse(response.body)['post_ids'] }
  .fan_out { |id| { method: :get, path: "/posts/#{id}" } }
  .collect
```

## RequestFlow Steps

| Step             | Purpose                        |
|------------------|--------------------------------|
| `fetch`          | Sequential HTTP request        |
| `then`           | Transform current result       |
| `fan_out`        | Concurrent requests from array |
| `filter`         | Filter array items             |
| `map`            | Transform each item            |
| `parallel_map`   | Ractor CPU parallelism         |
| `async_map`      | Fork CPU parallelism           |
| `concurrent_map` | Thread CPU parallelism         |
| `process`        | Auto-detect best processor     |
| `collect`        | Execute, return result         |

## Streaming Fan-Out

Default behavior streams responses to the next step as they complete.

### Parameters

| Parameter      | Default        | Options                                   |
|----------------|----------------|-------------------------------------------|
| `on_ready`     | `:stream`      | `:stream`, `:batch`, `Proc`               |
| `on_fail`      | `:fail_fast`   | `:skip`, `:fail_fast`, `:collect`, `Proc` |
| `order`        | `:preserve`    | `:preserve`, `:arrival`                   |
| `max_inflight` | `nproc × √2`   | Integer                                   |
| `timeout_ms`   | config default | Integer (milliseconds)                    |
| `retries`      | exponential    | `{max:, backoff:}` or `false`             |

### Streaming (Default)

```ruby
# Responses stream to next step as they arrive
client.request_flow
  .fetch(:get, '/users/123')
  .then { |r| JSON.parse(r.body)['post_ids'] }
  .fan_out { |id| { method: :get, path: "/posts/#{id}" } }
  .parallel_map
  .collect
```

### Batch Mode

```ruby
# Wait for all responses before proceeding (legacy behavior)
client.request_flow
  .fetch(:get, '/users/123')
  .then { |r| JSON.parse(r.body)['post_ids'] }
  .fan_out(on_ready: :batch) { |id| { method: :get, path: "/posts/#{id}" } }
  .collect
```

### Error Handling

```ruby
# Skip failed requests
fan_out(on_fail: :skip) { |id| ... }

# Collect failures, raise at end
fan_out(on_fail: :collect) { |id| ... }

# Custom handler
fan_out(on_fail: ->(error, request) {
  logger.warn("Failed: #{request[:path]}")
  { error: error.message }  # fallback value
}) { |id| ... }
```

### Retry Configuration

```ruby
# Retry with exponential backoff (default)
fan_out(retries: { max: 3 }) { |id| ... }

# Linear backoff
fan_out(retries: { max: 2, backoff: :linear }) { |id| ... }

# Disable retries
fan_out(retries: false) { |id| ... }
```

### Timeout and Backpressure

```ruby
fan_out(
  timeout_ms: 5000,      # 5s per request
  max_inflight: 20       # Max concurrent requests
) { |id| ... }
```

### Order Control

```ruby
# Preserve input order (default) - results reordered to match input
fan_out(order: :preserve) { |id| ... }

# Arrival order - results in completion order (faster)
fan_out(order: :arrival) { |id| ... }
```

## Chaining

```ruby
results = client.request_flow
  .fetch(:get, '/items')
  .then { |r| JSON.parse(r.body)['items'] }
  .filter { |item| item['active'] }
  .map { |item| item['id'] }
  .fan_out { |id| { method: :get, path: "/items/#{id}/details" } }
  .collect
```

## With CPU Parallelism

```ruby
posts = client.request_flow
  .fetch(:get, '/users/123')
  .then { |r| JSON.parse(r.body)['post_ids'] }
  .fan_out { |id| { method: :get, path: "/posts/#{id}" } }
  .parallel_map(recipe: Transforms::Recipe.default)   # Ractor
  # OR .async_map(...)        # Fork
  # OR .concurrent_map(...)   # Thread
  # OR .process(...)          # Auto-detect best processor
  .collect
```

## Reset for Reuse

```ruby
flow = client.request_flow
results1 = flow.fetch(:get, '/a').collect
flow.reset
results2 = flow.fetch(:get, '/b').collect
```
