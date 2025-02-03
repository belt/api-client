---
title: "Async Adapter"
audience_chain:
  - "developer"
  - "maintainer"
parent: "onboarding.http.md"
semantic_version: "1.0"
last_updated_at: "2026-02-06"
---
# Async Adapter

Fiber-based concurrency (Ruby 3+). See [onboarding.http.md](onboarding.http.md).

## Installation

```ruby
gem 'async'
gem 'async-http'
```

## Features

| Feature     | Value          |
|-------------|----------------|
| Concurrency | Fibers         |
| Memory      | ~2KB per fiber |
| I/O model   | Non-blocking   |
| Ruby        | 3.0+           |

## How It Works

```ruby
Sync do |task|
  internet = Async::HTTP::Internet.new
  tasks = requests.map do |request|
    task.async { execute_request(internet, request) }
  end
  tasks.map(&:wait)
ensure
  internet&.close
end
```

## When to Use

- Many concurrent connections (thousands)
- Memory-constrained environments
- Ruby 3+ with fiber scheduler
- Typhoeus/libcurl unavailable
