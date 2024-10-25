# ApiClient Examples

Canonical `RequestFlow` examples covering every adapter × processor
permutation. Each class is a real-world use case that naturally fits its
combination.

## The Canonical Pattern

Every example follows the same five-step pipeline:

```text
fetch → then → fan_out → *_map/process → collect
  │       │        │            │            │
  │       │        │            │            └─ materialize results
  │       │        │            └─ CPU-bound transform (Processor)
  │       │        └─ I/O-bound concurrent HTTP (Adapter)
  │       └─ extract IDs/keys from response
  └─ single sequential request
```

```ruby
client.request_flow
  .fetch(:get, '/resource/123')
  .then { |r| JSON.parse(r.body)['child_ids'] }
  .fan_out(on_fail: :skip) { |id| { method: :get, path: "/children/#{id}" } }
  .parallel_map(extract: :body, transform: :json)
  .collect
```

The pattern separates two independent concerns:

- **I/O concurrency** — how HTTP requests execute (`fan_out` → Adapter)
- **CPU parallelism** — how responses transform (`*_map` → Processor)

Both auto-detect the best available runtime. Both degrade gracefully to
sequential when nothing else is installed.

## Adapter × Processor Matrix

- processor — `CanonicalExample` — use-case description

### Quick Reference (4×4)

```text
 ADAPTER (I/O) │ ractor           async            concurrent        sequential
  ╲  PROCESSOR │                                                        (CPU)
───────────────┼────────────────────────────────────────────────────────────────
typhoeus       │ OrderFulfiller   CatalogSearcher  ComplianceAuditor LegacyExporter
async          │ FeedIngestor     HealthChecker    NotifyDispatcher  ConfigSnapshot
concurrent     │ ThreatScanner    GeoResolver      PayReconciler     DepGraphBuilder
sequential     │ UserEnricher     LogAggregator    MetricsCollector  ReportGenerator
```

### Typhoeus (I/O)

- ractor     — `OrderFulfiller` — order inventory fan-out
- async      — `CatalogSearcher` — multi-provider search
- concurrent — `ComplianceAuditor` — audit log collection
- sequential — `LegacyExporter` — paginated data migration

### Async (I/O)

- ractor     — `FeedIngestor` — social feed normalization
- async      — `HealthChecker` — service health dashboard
- concurrent — `NotifyDispatcher` — multi-channel delivery
- sequential — `ConfigSnapshot` — environment config merge

### Concurrent (I/O)

- ractor     — `ThreatScanner` — threat intelligence scanning
- async      — `GeoResolver` — CDN latency probing
- concurrent — `PayReconciler` — gateway reconciliation
- sequential — `DepGraphBuilder` — package tree resolution

### Sequential (I/O)

- ractor     — `UserEnricher` — CRM profile enrichment
- async      — `LogAggregator` — time-series log parsing
- concurrent — `MetricsCollector` — monitoring aggregation
- sequential — `ReportGenerator` — rate-limited reporting

## Error Strategies

Each example ships with a default error strategy that fits its use case.
Specs exercise all four strategies against every example.

| Strategy     | Behavior                    | Typical Use       |
| ------------ | --------------------------- | ----------------- |
| `:fail_fast` | Raise on first error        | Compliance        |
| `:collect`   | Gather errors, raise at end | Reconciliation    |
| `:skip`      | Drop failed items, continue | Search, health    |
| `:replace`   | Substitute fallback value   | Config, reporting |

Fan-out (`on_fail`) and processor (`on_error`) strategies are independent.
A single flow can skip failed HTTP requests but collect processor errors,
or vice versa.

## Why the Combinations Exist

Different workloads have different bottlenecks:

```text
                    I/O-bound                    CPU-bound
                 ┌──────────────┐            ┌──────────────┐
  High-perf      │  Typhoeus    │            │  Ractor      │
  (native C)     │  HTTP/2      │            │  true ∥      │
                 ├──────────────┤            ├──────────────┤
  Fiber-based    │  Async       │            │  Async       │
  (cooperative)  │  Ruby 3+     │            │  fork-based  │
                 ├──────────────┤            ├──────────────┤
  Thread-based   │  Concurrent  │            │  Concurrent  │
  (portable)     │  any Ruby    │            │  any Ruby    │
                 ├──────────────┤            ├──────────────┤
  Minimal        │  Sequential  │            │  Sequential  │
  (zero deps)    │  always works│            │  always works│
                 └──────────────┘            └──────────────┘
```

The two registries are orthogonal. A Typhoeus fan-out can feed a
sequential processor (small payloads don't need parallelism). A
sequential fan-out can feed a Ractor pool (rate-limited API, heavy
parsing). The matrix isn't 16 configurations to manage — it's
4 + 4 independent choices that compose.

**Note**: Ractor was removed from I/O backends (conceptually wrong for
HTTP). It remains in CPU processors where true parallelism matters for
compute-heavy transformations.

## Class Constants

Every example exposes `ADAPTER` and `PROCESSOR` constants for spec
introspection:

```ruby
OrderFulfiller::ADAPTER    # => :typhoeus
OrderFulfiller::PROCESSOR  # => :ractor
```

## Custom Backends

The Backend Registry supports plugins for specialized HTTP backends.
See `net_http.rb` for a complete working example:

```ruby
# Register Net::HTTP backend
ApiClient::Examples::NetHttp.register!

# Use it
client = ApiClient::Base.new(adapter: :net_http)
```

Custom backends must implement `Backend::Interface`:
- `#execute(requests)` → `Array<Faraday::Response>`
- `#config` → `Configuration`

See [backend/README.md](../backend/README.md) for full documentation.

## Further Reading

- [architecture.md](../../doc/architecture.md) — System overview, registries
- [onboarding.md](../../doc/onboarding.md) — Quick start, configuration
- [RequestFlow deep dive](../../doc/onboarding.processing.request_flow.md)
