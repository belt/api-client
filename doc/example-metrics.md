---
title: "Example Client Metrics"
audience_chain: ["developer", "maintainer"]
semantic_version: "1.0"
last_updated_at: "2026-10-12"
---

## Example Clients Metrics

Performance metrics for the 16 canonical `RequestFlow`
examples, measured against an isolated Puma benchmark fixture on
localhost.

Regenerate with:

```sh
bundle exec rake examples:metrics
```

Each client executes its full pipeline
(fetch → then → fan_out → map → collect) 20 times.
Timing is the median wall-clock run. Memory and allocation
counts are per single invocation.

Each example runs NullCircuit baseline first (circuit disabled),
then Stoplight circuit breaker. Tables show both measurements
with NullCircuit as the first row.

## Environment

```text
Ruby:    4.0.7 (arm64-darwin23)
YJIT:    enabled
Server:  Puma (loopback only; benchmark task, not RSpec)
Network: loopback (127.0.0.1; benchmark task only)
```

## Processor x Adapter Matrix

Grouped by processor (fastest to slowest). Within each group,
clients sorted by Stoplight performance (fastest first).
NullCircuit baseline shown first for each client.

### sequential

| Client            | Circuit     | Adapter    | Med ms | CPU ms | Alloc | Retain |
| ----------------- | ----------- | ---------- | -----: | -----: | ----: | -----: |
| ConfigSnapshot    | NullCircuit | async      |   0.66 |   0.65 |   629 |     12 |
| ConfigSnapshot    | Stoplight   | async      |   0.65 |   0.65 |   629 |     12 |
| LegacyExporter    | NullCircuit | typhoeus   |   0.63 |   0.63 |   630 |     12 |
| LegacyExporter    | Stoplight   | typhoeus   |   0.66 |   0.64 |   630 |     12 |
| DepGraphBuilder   | NullCircuit | concurrent |   0.67 |   0.66 |   631 |     12 |
| DepGraphBuilder   | Stoplight   | concurrent |   0.67 |   0.66 |   631 |     12 |
| ReportGenerator   | NullCircuit | sequential |   0.67 |   0.65 |   628 |     12 |
| ReportGenerator   | Stoplight   | sequential |   0.68 |   0.68 |   628 |     12 |

### ractor

| Client            | Circuit     | Adapter    | Med ms | CPU ms | Alloc | Retain |
| ----------------- | ----------- | ---------- | -----: | -----: | ----: | -----: |
| OrderFulfiller    | NullCircuit | typhoeus   |   0.66 |   0.66 |   645 |     12 |
| OrderFulfiller    | Stoplight   | typhoeus   |   0.65 |   0.64 |   648 |     13 |
| UserEnricher      | NullCircuit | sequential |   0.66 |   0.65 |   650 |     12 |
| UserEnricher      | Stoplight   | sequential |   0.67 |   0.66 |   650 |     12 |
| ThreatScanner     | NullCircuit | concurrent |   0.67 |   0.67 |   650 |     12 |
| ThreatScanner     | Stoplight   | concurrent |   0.68 |   0.66 |   650 |     12 |
| FeedIngestor      | NullCircuit | async      |   0.68 |   0.68 |   648 |     12 |
| FeedIngestor      | Stoplight   | async      |   0.69 |   0.68 |   648 |     12 |

### async

| Client            | Circuit     | Adapter    | Med ms | CPU ms | Alloc | Retain |
| ----------------- | ----------- | ---------- | -----: | -----: | ----: | -----: |
| GeoResolver       | NullCircuit | concurrent |   0.67 |   0.66 |   650 |     12 |
| GeoResolver       | Stoplight   | concurrent |   0.67 |   0.67 |   650 |     12 |
| CatalogSearcher   | NullCircuit | typhoeus   |   0.68 |   0.67 |   645 |     12 |
| CatalogSearcher   | Stoplight   | typhoeus   |   0.67 |   0.65 |   645 |     12 |
| LogAggregator     | NullCircuit | sequential |   0.68 |   0.67 |   661 |     12 |
| LogAggregator     | Stoplight   | sequential |   0.69 |   0.68 |   661 |     12 |
| HealthChecker     | NullCircuit | async      |   0.68 |   0.65 |   650 |     12 |
| HealthChecker     | Stoplight   | async      |   0.69 |   0.68 |   650 |     12 |

### concurrent

| Client            | Circuit     | Adapter    | Med ms | CPU ms | Alloc | Retain |
| ----------------- | ----------- | ---------- | -----: | -----: | ----: | -----: |
| ComplianceAuditor | NullCircuit | typhoeus   |   0.68 |   0.68 |   650 |     12 |
| ComplianceAuditor | Stoplight   | typhoeus   |   0.67 |   0.65 |   650 |     12 |
| MetricsCollector  | NullCircuit | sequential |   0.68 |   0.67 |   651 |     12 |
| MetricsCollector  | Stoplight   | sequential |   0.68 |   0.67 |   651 |     12 |
| NotifyDispatcher  | NullCircuit | async      |   0.67 |   0.66 |   650 |     12 |
| NotifyDispatcher  | Stoplight   | async      |   0.69 |   0.68 |   650 |     12 |
| PayReconciler     | NullCircuit | concurrent |   0.68 |   0.67 |   650 |     12 |
| PayReconciler     | Stoplight   | concurrent |   0.69 |   0.68 |   650 |     12 |

## Per-Client Detail

### ConfigSnapshot

- Adapter: `async` (I/O)
- Processor: `sequential` (CPU)

#### NullCircuit (baseline)
- Median: 0.66 ms
- P95: 0.84 ms
- P99: 0.93 ms
- CPU time: 0.65 ms (user: 0.34, sys: 0.31)
- RSS peak delta: +0 KB
- RSS avg delta: 0.0 KB/invocation
- Allocated: 629 objects
- Retained: 12 objects

#### Stoplight (circuit breaker)
- Median: 0.65 ms
- P95: 0.74 ms
- P99: 0.94 ms
- CPU time: 0.65 ms (user: 0.35, sys: 0.3)
- RSS before: 87456 KB
- RSS peak delta: +0 KB
- RSS avg delta: 0.0 KB/invocation
- GC objects/invocation: 715
- Allocated: 629 objects
- Retained: 12 objects

#### Circuit Overhead
- Absolute: -0.01 ms
- Relative: -1.5%

### LegacyExporter

- Adapter: `typhoeus` (I/O)
- Processor: `sequential` (CPU)

#### NullCircuit (baseline)
- Median: 0.63 ms
- P95: 0.68 ms
- P99: 0.68 ms
- CPU time: 0.63 ms (user: 0.34, sys: 0.29)
- RSS peak delta: +0 KB
- RSS avg delta: 0.0 KB/invocation
- Allocated: 630 objects
- Retained: 12 objects

#### Stoplight (circuit breaker)
- Median: 0.66 ms
- P95: 0.91 ms
- P99: 1.02 ms
- CPU time: 0.64 ms (user: 0.34, sys: 0.3)
- RSS before: 87424 KB
- RSS peak delta: +0 KB
- RSS avg delta: 1.6 KB/invocation
- GC objects/invocation: 716
- Allocated: 630 objects
- Retained: 12 objects

#### Circuit Overhead
- Absolute: +0.03 ms
- Relative: +4.8%

### DepGraphBuilder

- Adapter: `concurrent` (I/O)
- Processor: `sequential` (CPU)

#### NullCircuit (baseline)
- Median: 0.67 ms
- P95: 0.88 ms
- P99: 0.94 ms
- CPU time: 0.66 ms (user: 0.37, sys: 0.29)
- RSS peak delta: +0 KB
- RSS avg delta: 0.0 KB/invocation
- Allocated: 631 objects
- Retained: 12 objects

#### Stoplight (circuit breaker)
- Median: 0.67 ms
- P95: 0.85 ms
- P99: 1.29 ms
- CPU time: 0.66 ms (user: 0.38, sys: 0.28)
- RSS before: 87088 KB
- RSS peak delta: +0 KB
- RSS avg delta: 0.0 KB/invocation
- GC objects/invocation: 717
- Allocated: 631 objects
- Retained: 12 objects

#### Circuit Overhead
- Absolute: +0.0 ms
- Relative: +0.0%

### ReportGenerator

- Adapter: `sequential` (I/O)
- Processor: `sequential` (CPU)

#### NullCircuit (baseline)
- Median: 0.67 ms
- P95: 0.95 ms
- P99: 0.96 ms
- CPU time: 0.65 ms (user: 0.35, sys: 0.3)
- RSS peak delta: +0 KB
- RSS avg delta: 0.0 KB/invocation
- Allocated: 628 objects
- Retained: 12 objects

#### Stoplight (circuit breaker)
- Median: 0.68 ms
- P95: 0.92 ms
- P99: 0.92 ms
- CPU time: 0.68 ms (user: 0.38, sys: 0.3)
- RSS before: 87056 KB
- RSS peak delta: +0 KB
- RSS avg delta: 0.0 KB/invocation
- GC objects/invocation: 714
- Allocated: 628 objects
- Retained: 12 objects

#### Circuit Overhead
- Absolute: +0.01 ms
- Relative: +1.5%

### OrderFulfiller

- Adapter: `typhoeus` (I/O)
- Processor: `ractor` (CPU)

#### NullCircuit (baseline)
- Median: 0.66 ms
- P95: 0.8 ms
- P99: 0.9 ms
- CPU time: 0.66 ms (user: 0.36, sys: 0.3)
- RSS peak delta: +0 KB
- RSS avg delta: 0.0 KB/invocation
- Allocated: 645 objects
- Retained: 12 objects

#### Stoplight (circuit breaker)
- Median: 0.65 ms
- P95: 0.93 ms
- P99: 0.95 ms
- CPU time: 0.64 ms (user: 0.34, sys: 0.3)
- RSS before: 87104 KB
- RSS peak delta: +0 KB
- RSS avg delta: 0.0 KB/invocation
- GC objects/invocation: 739
- Allocated: 648 objects
- Retained: 13 objects

#### Circuit Overhead
- Absolute: -0.01 ms
- Relative: -1.5%

### UserEnricher

- Adapter: `sequential` (I/O)
- Processor: `ractor` (CPU)

#### NullCircuit (baseline)
- Median: 0.66 ms
- P95: 0.76 ms
- P99: 0.95 ms
- CPU time: 0.65 ms (user: 0.36, sys: 0.29)
- RSS peak delta: +0 KB
- RSS avg delta: 0.0 KB/invocation
- Allocated: 650 objects
- Retained: 12 objects

#### Stoplight (circuit breaker)
- Median: 0.67 ms
- P95: 0.93 ms
- P99: 1.0 ms
- CPU time: 0.66 ms (user: 0.36, sys: 0.3)
- RSS before: 87648 KB
- RSS peak delta: +0 KB
- RSS avg delta: 0.8 KB/invocation
- GC objects/invocation: 744
- Allocated: 650 objects
- Retained: 12 objects

#### Circuit Overhead
- Absolute: +0.01 ms
- Relative: +1.5%

### ThreatScanner

- Adapter: `concurrent` (I/O)
- Processor: `ractor` (CPU)

#### NullCircuit (baseline)
- Median: 0.67 ms
- P95: 0.78 ms
- P99: 0.92 ms
- CPU time: 0.67 ms (user: 0.37, sys: 0.3)
- RSS peak delta: +0 KB
- RSS avg delta: 0.0 KB/invocation
- Allocated: 650 objects
- Retained: 12 objects

#### Stoplight (circuit breaker)
- Median: 0.68 ms
- P95: 0.85 ms
- P99: 0.93 ms
- CPU time: 0.66 ms (user: 0.37, sys: 0.29)
- RSS before: 87456 KB
- RSS peak delta: +0 KB
- RSS avg delta: 0.0 KB/invocation
- GC objects/invocation: 744
- Allocated: 650 objects
- Retained: 12 objects

#### Circuit Overhead
- Absolute: +0.01 ms
- Relative: +1.5%

### FeedIngestor

- Adapter: `async` (I/O)
- Processor: `ractor` (CPU)

#### NullCircuit (baseline)
- Median: 0.68 ms
- P95: 0.92 ms
- P99: 1.0 ms
- CPU time: 0.68 ms (user: 0.37, sys: 0.31)
- RSS peak delta: +80 KB
- RSS avg delta: 8.8 KB/invocation
- Allocated: 648 objects
- Retained: 12 objects

#### Stoplight (circuit breaker)
- Median: 0.69 ms
- P95: 1.36 ms
- P99: 1.46 ms
- CPU time: 0.68 ms (user: 0.37, sys: 0.31)
- RSS before: 86848 KB
- RSS peak delta: +32 KB
- RSS avg delta: 4.8 KB/invocation
- GC objects/invocation: 742
- Allocated: 648 objects
- Retained: 12 objects

#### Circuit Overhead
- Absolute: +0.01 ms
- Relative: +1.5%

### GeoResolver

- Adapter: `concurrent` (I/O)
- Processor: `async` (CPU)

#### NullCircuit (baseline)
- Median: 0.67 ms
- P95: 0.86 ms
- P99: 0.92 ms
- CPU time: 0.66 ms (user: 0.36, sys: 0.3)
- RSS peak delta: +0 KB
- RSS avg delta: 0.0 KB/invocation
- Allocated: 650 objects
- Retained: 12 objects

#### Stoplight (circuit breaker)
- Median: 0.67 ms
- P95: 0.85 ms
- P99: 0.95 ms
- CPU time: 0.67 ms (user: 0.35, sys: 0.32)
- RSS before: 87104 KB
- RSS peak delta: +0 KB
- RSS avg delta: 0.0 KB/invocation
- GC objects/invocation: 744
- Allocated: 650 objects
- Retained: 12 objects

#### Circuit Overhead
- Absolute: +0.0 ms
- Relative: +0.0%

### CatalogSearcher

- Adapter: `typhoeus` (I/O)
- Processor: `async` (CPU)

#### NullCircuit (baseline)
- Median: 0.68 ms
- P95: 0.73 ms
- P99: 0.94 ms
- CPU time: 0.67 ms (user: 0.37, sys: 0.3)
- RSS peak delta: +0 KB
- RSS avg delta: 0.0 KB/invocation
- Allocated: 645 objects
- Retained: 12 objects

#### Stoplight (circuit breaker)
- Median: 0.67 ms
- P95: 0.98 ms
- P99: 0.99 ms
- CPU time: 0.65 ms (user: 0.37, sys: 0.28)
- RSS before: 87104 KB
- RSS peak delta: +0 KB
- RSS avg delta: 0.8 KB/invocation
- GC objects/invocation: 739
- Allocated: 645 objects
- Retained: 12 objects

#### Circuit Overhead
- Absolute: -0.01 ms
- Relative: -1.5%

### LogAggregator

- Adapter: `sequential` (I/O)
- Processor: `async` (CPU)

#### NullCircuit (baseline)
- Median: 0.68 ms
- P95: 1.03 ms
- P99: 1.13 ms
- CPU time: 0.67 ms (user: 0.38, sys: 0.29)
- RSS peak delta: +0 KB
- RSS avg delta: 0.0 KB/invocation
- Allocated: 661 objects
- Retained: 12 objects

#### Stoplight (circuit breaker)
- Median: 0.69 ms
- P95: 0.95 ms
- P99: 1.81 ms
- CPU time: 0.68 ms (user: 0.4, sys: 0.28)
- RSS before: 87008 KB
- RSS peak delta: +16 KB
- RSS avg delta: 3.2 KB/invocation
- GC objects/invocation: 758
- Allocated: 661 objects
- Retained: 12 objects

#### Circuit Overhead
- Absolute: +0.01 ms
- Relative: +1.5%

### HealthChecker

- Adapter: `async` (I/O)
- Processor: `async` (CPU)

#### NullCircuit (baseline)
- Median: 0.68 ms
- P95: 0.74 ms
- P99: 0.85 ms
- CPU time: 0.65 ms (user: 0.36, sys: 0.29)
- RSS peak delta: +0 KB
- RSS avg delta: 0.0 KB/invocation
- Allocated: 650 objects
- Retained: 12 objects

#### Stoplight (circuit breaker)
- Median: 0.69 ms
- P95: 0.93 ms
- P99: 0.96 ms
- CPU time: 0.68 ms (user: 0.37, sys: 0.31)
- RSS before: 87072 KB
- RSS peak delta: +0 KB
- RSS avg delta: 0.0 KB/invocation
- GC objects/invocation: 744
- Allocated: 650 objects
- Retained: 12 objects

#### Circuit Overhead
- Absolute: +0.01 ms
- Relative: +1.5%

### ComplianceAuditor

- Adapter: `typhoeus` (I/O)
- Processor: `concurrent` (CPU)

#### NullCircuit (baseline)
- Median: 0.68 ms
- P95: 0.81 ms
- P99: 1.01 ms
- CPU time: 0.68 ms (user: 0.38, sys: 0.3)
- RSS peak delta: +0 KB
- RSS avg delta: 0.0 KB/invocation
- Allocated: 650 objects
- Retained: 12 objects

#### Stoplight (circuit breaker)
- Median: 0.67 ms
- P95: 0.93 ms
- P99: 0.94 ms
- CPU time: 0.65 ms (user: 0.35, sys: 0.3)
- RSS before: 87088 KB
- RSS peak delta: +0 KB
- RSS avg delta: 0.0 KB/invocation
- GC objects/invocation: 744
- Allocated: 650 objects
- Retained: 12 objects

#### Circuit Overhead
- Absolute: -0.01 ms
- Relative: -1.5%

### MetricsCollector

- Adapter: `sequential` (I/O)
- Processor: `concurrent` (CPU)

#### NullCircuit (baseline)
- Median: 0.68 ms
- P95: 0.89 ms
- P99: 0.89 ms
- CPU time: 0.67 ms (user: 0.37, sys: 0.3)
- RSS peak delta: +0 KB
- RSS avg delta: 0.0 KB/invocation
- Allocated: 651 objects
- Retained: 12 objects

#### Stoplight (circuit breaker)
- Median: 0.68 ms
- P95: 1.08 ms
- P99: 1.46 ms
- CPU time: 0.67 ms (user: 0.37, sys: 0.3)
- RSS before: 87120 KB
- RSS peak delta: +0 KB
- RSS avg delta: 15.2 KB/invocation
- GC objects/invocation: 745
- Allocated: 651 objects
- Retained: 12 objects

#### Circuit Overhead
- Absolute: +0.0 ms
- Relative: +0.0%

### NotifyDispatcher

- Adapter: `async` (I/O)
- Processor: `concurrent` (CPU)

#### NullCircuit (baseline)
- Median: 0.67 ms
- P95: 0.93 ms
- P99: 0.94 ms
- CPU time: 0.66 ms (user: 0.34, sys: 0.32)
- RSS peak delta: +0 KB
- RSS avg delta: 0.0 KB/invocation
- Allocated: 650 objects
- Retained: 12 objects

#### Stoplight (circuit breaker)
- Median: 0.69 ms
- P95: 1.02 ms
- P99: 1.17 ms
- CPU time: 0.68 ms (user: 0.38, sys: 0.3)
- RSS before: 86976 KB
- RSS peak delta: +0 KB
- RSS avg delta: 0.8 KB/invocation
- GC objects/invocation: 744
- Allocated: 650 objects
- Retained: 12 objects

#### Circuit Overhead
- Absolute: +0.02 ms
- Relative: +3.0%

### PayReconciler

- Adapter: `concurrent` (I/O)
- Processor: `concurrent` (CPU)

#### NullCircuit (baseline)
- Median: 0.68 ms
- P95: 0.85 ms
- P99: 0.87 ms
- CPU time: 0.67 ms (user: 0.37, sys: 0.3)
- RSS peak delta: +0 KB
- RSS avg delta: 0.0 KB/invocation
- Allocated: 650 objects
- Retained: 12 objects

#### Stoplight (circuit breaker)
- Median: 0.69 ms
- P95: 0.92 ms
- P99: 1.0 ms
- CPU time: 0.68 ms (user: 0.37, sys: 0.31)
- RSS before: 87088 KB
- RSS peak delta: +0 KB
- RSS avg delta: 0.8 KB/invocation
- GC objects/invocation: 744
- Allocated: 650 objects
- Retained: 12 objects

#### Circuit Overhead
- Absolute: +0.01 ms
- Relative: +1.5%

## Methodology

1. Global warmup: 3 invocations with throwaway clients to
   warm JIT and benchmark fixture (excluded from metrics)
2. All 16 clients pre-warmed (both NullCircuit and Stoplight
   variants) — connections established before any measurement
3. Examples run in randomized order to avoid bias
4. Each example runs NullCircuit baseline first, then
   Stoplight circuit breaker (back-to-back for thermal
   consistency)
5. 20 timed invocations measure steady-state
   performance with connection reuse — median, P95, P99 reported
6. Connection establishment overhead (TCP handshake; no TLS)
   is absorbed during pre-warm, excluded from metrics
7. CPU time: `Process.times` user+system delta per
   invocation (median reported)
8. P95/P99: nearest-rank percentile over wall-clock times
   — filters single-iteration outliers (GC, CoW faults)
9. RSS peak delta: P95 of per-iteration RSS deltas
   (filters single-iteration outliers from CoW faults,
   lazy page mapping, or GC compaction artifacts)
10. RSS avg delta: mean of per-iteration deltas
    reported as float to surface sub-KB changes
11. RSS stabilization: double GC pass (start + compact +
    start) before each iteration — second pass reclaims
    pages dirtied by compaction on macOS
12. GC objects/invocation: `GC.stat(:total_allocated_objects)`
    delta per iteration (median), independent of RSS
13. Allocations: `memory_profiler` single-invocation report
    (if available)
14. NullCircuit: `circuit_config.enabled = false` forces
    `NullCircuit` (pass-through `yield`) — no state machine,
    no failure tracking, no mutex synchronization
15. Circuit Overhead: Stoplight median - NullCircuit median
16. Tables grouped by processor, sorted by Stoplight median
    latency within each group (fastest first)

## See Also

- [Examples README](../lib/api_client/examples/README.md)
- [Architecture](architecture.md)
- [Circuit Breaker](circuit-breaker.md)
- [Profiling](../lib/api_client/profiling.rb)
