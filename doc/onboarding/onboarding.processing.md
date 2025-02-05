---
title: "Processing Concepts"
audience_chain:
  - "developer"
  - "maintainer"
parent: "../onboarding.md"
semantic_version: "1.0"
last_updated_at: "2026-02-06"
---
# Processing Concepts

CPU-parallel response processing.

## Processor Selection

`Processing::Registry.detect` → Ractor > AsyncProcessor > ConcurrentProcessor > Sequential

| Processor  | Parallelism       | Platform  | Best For                   |
|------------|-------------------|-----------|----------------------------|
| Ractor     | True (per-Ractor) | Ruby 3.0+ | Fine-grained, experimental |
| Async      | True (fork)       | Unix      | Production, coarse-grained |
| Concurrent | GVL-limited*      | All       | JRuby, mixed I/O+CPU       |

*JRuby/TruffleRuby achieve true parallelism.

## Built-in Extractors

| Extractor   | Extracts                  |
|-------------|---------------------------|
| `:body`     | `response.body` (default) |
| `:status`   | `response.status`         |
| `:headers`  | `response.headers.to_h`   |
| `:identity` | Response as-is            |

## Built-in Transforms

| Transform   | Operation                        |
|-------------|----------------------------------|
| `:json`     | `JSON.parse(data)` (default)     |
| `:sha256`   | `Digest::SHA256.hexdigest(data)` |
| `:identity` | Pass-through                     |

## Error Handling

`Processing::ErrorStrategy` is a `Data.define` value object:

| Strategy     | Behavior                                |
|--------------|-----------------------------------------|
| `:fail_fast` | Raise on first error                    |
| `:collect`   | Raise with partial results in exception |
| `:skip`      | Omit failed items from results          |
| `:replace`   | Substitute fallback value               |

```ruby
Processing::ErrorStrategy.fail_fast       # default
Processing::ErrorStrategy.collect
Processing::ErrorStrategy.skip
Processing::ErrorStrategy.replace({})     # with fallback value
```

## RequestFlow Integration

```ruby
client.request_flow
  .fetch(:get, '/users/123')
  .then { |r| JSON.parse(r.body)['post_ids'] }
  .fan_out { |id| { method: :get, path: "/posts/#{id}" } }
  .parallel_map(recipe: Transforms::Recipe.default)   # Ractor
  # OR .async_map(...)        # Fork
  # OR .concurrent_map(...)   # Thread
  # OR .process(...)          # Auto-detect best processor
  .collect
```

## Transforms::Recipe

A `Data.define` value object specifying the two-stage pipeline: extract data
from response, then apply a transformation.

```ruby
Transforms::Recipe.default   # extract: :body, transform: :json
Transforms::Recipe.identity  # extract: :body, transform: :identity
Transforms::Recipe.headers   # extract: :headers, transform: :identity
Transforms::Recipe.status    # extract: :status, transform: :identity

# Custom recipe
Transforms::Recipe.new(extract: :body, transform: :sha256)
```

## Direct Usage

```ruby
processor = ApiClient::Processing::RactorProcessor.new
# OR AsyncProcessor.new | ConcurrentProcessor.new

parsed = processor.map(responses, recipe: Transforms::Recipe.default)
large = processor.select(responses) { |d| d['size'] > 1000 }
total = processor.reduce(responses, 0) { |sum, d| sum + d['count'] }
```

## Instrumentation

`ActiveSupport::Notifications` events (`{processor}` = ractor | async_processor | concurrent_processor):

| Event Pattern                     | Payload                                    |
|-----------------------------------|--------------------------------------------|
| `api_client.{processor}.start`    | `operation`, `count`, `pool_size`          |
| `api_client.{processor}.complete` | `operation`, `input_count`, `output_count` |
| `api_client.{processor}.error`    | `index`, `error`, `strategy`               |

## Processor Guides

[ractor](onboarding.processing.ractor.md) |
[async](onboarding.processing.async.md) |
[concurrent](onboarding.processing.concurrent.md) |
[request_flow](onboarding.processing.request_flow.md)

## Auto-Detection

Use `process` step in RequestFlow to auto-detect the best available processor:

```ruby
client.request_flow
  .fetch(:get, '/data')
  .then { |r| JSON.parse(r.body)['items'] }
  .process { |item| expensive_transform(item) }
  .collect
```
