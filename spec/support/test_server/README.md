# Test Server

Real TCP server for integration specs. Runs Falcon in an
`Async::Container::Threaded` so tests hit actual HTTP endpoints over
`127.0.0.1`.

## Why it exists

Unit specs stub HTTP via WebMock (`MockHttpHelper`). Integration specs
need real TCP behavior — timeouts, connection refusals, circuit breaker
trips, and end-to-end adapter verification. This server provides that.

## Structure

```text
test_server/
├── server.rb          # Falcon lifecycle (start/stop/port allocation)
├── router.rb          # Prefix-based dispatch to route modules
└── routes/
    ├── base.rb        # Shared route helpers
    ├── core.rb        # /health, /users, /posts (broad)
    ├── orders.rb      # /orders (OrderFulfiller)
    ├── catalog.rb     # /catalog (CatalogSearcher)
    ├── compliance.rb  # /compliance (ComplianceAuditor)
    ├── ...            # One file per example domain
    └── registry.rb    # /registry
```

Each route file in `routes/` backs one or more
[canonical examples](../../../lib/api_client/examples/README.md).

## Usage

Integration specs include the `:integration` tag, which activates a
shared context that boots the server and exposes `client_for_server`:

```ruby
RSpec.describe MyFeature, :integration do
  it "handles real HTTP" do
    response = client_for_server.get("/health")
    expect(response.status).to eq(200)
  end
end
```

## When to use what

| Need                          | Tool            |
|-------------------------------|-----------------|
| Fast, deterministic unit test | `MockHttpHelper` / WebMock |
| Real TCP, timeouts, failures  | `TestServer`    |
