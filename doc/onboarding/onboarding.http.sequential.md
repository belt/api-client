---
title: "Sequential Adapter"
audience_chain:
  - "developer"
  - "maintainer"
parent: "onboarding.http.md"
semantic_version: "1.0"
last_updated_at: "2026-02-06"
---
# Sequential Adapter

One request at a time. See [onboarding.http.md](onboarding.http.md).

## Installation

No additional gems required.

## Features

| Feature        | Value   |
|----------------|---------|
| Concurrency    | None    |
| Dependencies   | None    |
| Memory         | Minimal |
| Predictability | High    |

## How It Works

```ruby
requests.map { |req| Orchestrators.execute_request(connection, req) }
```

## When to Use

- Testing/development
- Rate-limited APIs
- Debugging request order
- Minimal dependencies required
