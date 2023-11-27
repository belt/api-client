# Backend System

HTTP backend registry with auto-detection and plugin support.

## Overview

The Backend system manages I/O-bound HTTP request execution with different
concurrency models. Core backends are auto-detected in priority order, and
custom backends can be registered via the plugin API.

## Core Backends

Detection order (best-of-breed first):

1. **Typhoeus** - HTTP/2, pipelining, Hydra concurrency (requires `gem 'typhoeus'`)
2. **Async** - Fiber-based, Ruby 3+ optimized (requires `gem 'async-http'`)
3. **Concurrent** - Thread pool based (requires `gem 'concurrent-ruby'`)
4. **Sequential** - Fallback (always available)

## Auto-Detection

```ruby
# Automatically uses best available backend
client = ApiClient::Base.new(url: 'https://api.example.com')
response = client.get('/users')

# Check which backend was selected
backend_name = ApiClient::Backend.detect
# => :typhoeus (if available), :async, :concurrent, or :sequential
```

## Force Specific Backend

```ruby
client = ApiClient::Base.new(
  url: 'https://api.example.com',
  adapter: :concurrent  # Force concurrent backend
)
```

## Custom Backends

Register custom backends for specialized use cases:

```ruby
class MyCustomBackend
  include ApiClient::Backend::Interface

  attr_reader :config

  def initialize(config = ApiClient.configuration)
    @config = config
  end

  def execute(requests)
    # Implement HTTP request execution
    # Must return Array<Faraday::Response>
    requests.map { |req| make_http_call(req) }
  end
end

# Register the backend
ApiClient::Backend.register(:my_backend, MyCustomBackend)

# Use it
client = ApiClient::Base.new(
  url: 'https://api.example.com',
  adapter: :my_backend
)
```

## Backend Interface Contract

All backends must implement:

### Required Methods

- `#execute(requests)` - Execute HTTP requests
  - **Input**: `Array<Hash>` with keys: `:method`, `:path`, `:headers`, `:params`, `:body`
  - **Output**: `Array<Faraday::Response>` in same order as input
- `#config` - Return `ApiClient::Configuration` instance

### Response Format

Backends must return `Faraday::Response` objects to maintain compatibility:

```ruby
env = Faraday::Env.new.tap do |faraday_env|
  faraday_env.status = 200
  faraday_env.response_headers = {"content-type" => "application/json"}
  faraday_env.body = '{"id": 1}'
  faraday_env.url = URI.parse("https://api.example.com/users/1")
end

Faraday::Response.new(env)
```

## Backend vs Processor

**Backends** (I/O-bound):
- Handle HTTP request execution
- Concurrency models: libcurl, fibers, threads
- Located in `lib/api_client/adapters/`
- Registry: `Backend::Registry`

**Processors** (CPU-bound):
- Handle data transformation after HTTP
- Parallelism models: Ractors, forks, threads
- Located in `lib/api_client/processing/`
- Registry: `Processing::Registry`

## API Reference

### Backend Module

```ruby
# Register custom backend
ApiClient::Backend.register(name, klass)

# Auto-detect best backend
ApiClient::Backend.detect  # => :typhoeus, :async, :concurrent, or :sequential

# Resolve backend name to class
ApiClient::Backend.resolve(:typhoeus)  # => ApiClient::Adapters::TyphoeusAdapter

# Check availability
ApiClient::Backend.available?(:async)  # => true/false

# List all available backends
ApiClient::Backend.available  # => [:typhoeus, :concurrent, :sequential]

# Reverse lookup: class → name
ApiClient::Backend.backend_name(klass)  # => :typhoeus
```

### Backend::Registry

Lower-level registry access (same methods as Backend module):

```ruby
ApiClient::Backend::Registry.detect
ApiClient::Backend::Registry.resolve(:concurrent)
ApiClient::Backend::Registry.available?(:async)
```

## Examples

See `lib/api_client/examples/net_http.rb` for a complete
working example of registering and using a custom backend.

## Backward Compatibility

`Adapters::Registry` still exists as a compatibility shim that delegates
to `Backend::Registry`. New code should use `Backend` directly:

```ruby
# Old (still works)
ApiClient::Adapters::Registry.detect

# New (preferred)
ApiClient::Backend.detect
```

## Further Reading

- [architecture.md](../../doc/architecture.md) - System architecture overview
- [net_http.rb](../examples/net_http.rb) - Complete example
- [interface.rb](interface.rb) - Backend interface contract
- [registry.rb](registry.rb) - Registry implementation
