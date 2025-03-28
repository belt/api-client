---
title: "Example Client Metrics"
audience_chain: ["developer", "maintainer"]
semantic_version: "1.0"
last_updated_at: "2026-02-09"
---

## Example Clients Metrics

Performance metrics for the 16 canonical `RequestFlow`
examples, measured against a custom Falcon test server on
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
Ruby:    4.0.1 (x86_64-darwin25)
YJIT:    enabled
Server:  Falcon (Async::Container::Threaded, 12 workers)
Network: loopback (127.0.0.1)
```

## Processor x Adapter Matrix

Grouped by processor (fastest to slowest). Within each group,
clients sorted by Stoplight performance (fastest first).
NullCircuit baseline shown first for each client.

### concurrent

| Client            | Circuit     | Adapter    | Med ms | CPU ms | Alloc | Retain |
| ----------------- | ----------- | ---------- | -----: | -----: | ----: | -----: |
| PayReconciler     | NullCircuit | concurrent |   1.73 |   1.69 |   884 |     14 |
| PayReconciler     | Stoplight   | concurrent |   1.72 |    1.7 |   884 |     14 |
| ComplianceAuditor | NullCircuit | typhoeus   |   1.71 |   1.68 |   884 |     14 |
| ComplianceAuditor | Stoplight   | typhoeus   |    1.8 |   1.79 |   884 |     14 |
| NotifyDispatcher  | NullCircuit | async      |   1.74 |   1.71 |   884 |     14 |
| NotifyDispatcher  | Stoplight   | async      |   1.83 |    1.8 |   884 |     14 |
| MetricsCollector  | NullCircuit | sequential |    2.2 |   2.14 |   885 |     14 |
| MetricsCollector  | Stoplight   | sequential |   2.14 |    2.1 |   885 |     14 |

### async

| Client            | Circuit     | Adapter    | Med ms | CPU ms | Alloc | Retain |
| ----------------- | ----------- | ---------- | -----: | -----: | ----: | -----: |
| CatalogSearcher   | NullCircuit | typhoeus   |   1.78 |   1.75 |   878 |     14 |
| CatalogSearcher   | Stoplight   | typhoeus   |   1.78 |   1.77 |   878 |     14 |
| LogAggregator     | NullCircuit | sequential |   2.11 |   2.06 |   894 |     14 |
| LogAggregator     | Stoplight   | sequential |   1.83 |   1.79 |   894 |     14 |
| GeoResolver       | NullCircuit | concurrent |   2.03 |   1.97 |   884 |     14 |
| GeoResolver       | Stoplight   | concurrent |   2.01 |    2.0 |   884 |     14 |
| HealthChecker     | NullCircuit | async      |   2.17 |    2.1 |   884 |     14 |
| HealthChecker     | Stoplight   | async      |   2.09 |   2.01 |   884 |     14 |

### sequential

| Client            | Circuit     | Adapter    | Med ms | CPU ms | Alloc | Retain |
| ----------------- | ----------- | ---------- | -----: | -----: | ----: | -----: |
| DepGraphBuilder   | NullCircuit | concurrent |   2.04 |   2.01 |   860 |     14 |
| DepGraphBuilder   | Stoplight   | concurrent |   1.94 |   1.92 |   860 |     14 |
| LegacyExporter    | NullCircuit | typhoeus   |   2.07 |   2.04 |   859 |     14 |
| LegacyExporter    | Stoplight   | typhoeus   |   1.97 |   1.92 |   859 |     14 |
| ConfigSnapshot    | NullCircuit | async      |   2.05 |   2.03 |   858 |     14 |
| ConfigSnapshot    | Stoplight   | async      |   2.06 |   2.03 |   858 |     14 |
| ReportGenerator   | NullCircuit | sequential |    2.0 |   1.98 |   857 |     14 |
| ReportGenerator   | Stoplight   | sequential |   2.17 |    2.1 |   857 |     14 |

### ractor

| Client            | Circuit     | Adapter    | Med ms | CPU ms | Alloc | Retain |
| ----------------- | ----------- | ---------- | -----: | -----: | ----: | -----: |
| FeedIngestor      | NullCircuit | async      |   1.82 |   1.85 |   882 |     14 |
| FeedIngestor      | Stoplight   | async      |   1.94 |   1.93 |   882 |     14 |
| OrderFulfiller    | NullCircuit | typhoeus   |   2.04 |   1.99 |   878 |     14 |
| OrderFulfiller    | Stoplight   | typhoeus   |   2.02 |   1.99 |   878 |     14 |
| UserEnricher      | NullCircuit | sequential |   2.03 |    2.0 |   884 |     14 |
| UserEnricher      | Stoplight   | sequential |    2.1 |   2.05 |   884 |     14 |
| ThreatScanner     | NullCircuit | concurrent |   1.99 |   1.96 |   884 |     14 |
| ThreatScanner     | Stoplight   | concurrent |   2.13 |   2.13 |   884 |     14 |

## Per-Client Detail

### PayReconciler

- Adapter: `concurrent` (I/O)
- Processor: `concurrent` (CPU)

#### NullCircuit (baseline)
- Median: 1.73 ms
- P95: 1.88 ms
- P99: 2.46 ms
- CPU time: 1.69 ms (user: 1.19, sys: 0.5)
- RSS peak delta: +0 KB
- RSS avg delta: 0.0 KB/invocation
- Allocated: 884 objects
- Retained: 14 objects

#### Stoplight (circuit breaker)
- Median: 1.72 ms
- P95: 2.46 ms
- P99: 4.64 ms
- CPU time: 1.7 ms (user: 1.21, sys: 0.49)
- RSS before: 74256 KB
- RSS peak delta: +20 KB
- RSS avg delta: 4.8 KB/invocation
- GC objects/invocation: 1015
- Allocated: 884 objects
- Retained: 14 objects

#### Circuit Overhead
- Absolute: -0.01 ms
- Relative: -0.6%

### ComplianceAuditor

- Adapter: `typhoeus` (I/O)
- Processor: `concurrent` (CPU)

#### NullCircuit (baseline)
- Median: 1.71 ms
- P95: 2.54 ms
- P99: 3.87 ms
- CPU time: 1.68 ms (user: 1.18, sys: 0.5)
- RSS peak delta: +8 KB
- RSS avg delta: 2.2 KB/invocation
- Allocated: 884 objects
- Retained: 14 objects

#### Stoplight (circuit breaker)
- Median: 1.8 ms
- P95: 2.6 ms
- P99: 4.92 ms
- CPU time: 1.79 ms (user: 1.26, sys: 0.53)
- RSS before: 73780 KB
- RSS peak delta: +8 KB
- RSS avg delta: 1.0 KB/invocation
- GC objects/invocation: 1015
- Allocated: 884 objects
- Retained: 14 objects

#### Circuit Overhead
- Absolute: +0.09 ms
- Relative: +5.3%

### NotifyDispatcher

- Adapter: `async` (I/O)
- Processor: `concurrent` (CPU)

#### NullCircuit (baseline)
- Median: 1.74 ms
- P95: 2.1 ms
- P99: 2.49 ms
- CPU time: 1.71 ms (user: 1.21, sys: 0.5)
- RSS peak delta: +0 KB
- RSS avg delta: 0.0 KB/invocation
- Allocated: 884 objects
- Retained: 14 objects

#### Stoplight (circuit breaker)
- Median: 1.83 ms
- P95: 2.81 ms
- P99: 5.45 ms
- CPU time: 1.8 ms (user: 1.28, sys: 0.52)
- RSS before: 74372 KB
- RSS peak delta: +0 KB
- RSS avg delta: 1.4 KB/invocation
- GC objects/invocation: 1015
- Allocated: 884 objects
- Retained: 14 objects

#### Circuit Overhead
- Absolute: +0.09 ms
- Relative: +5.2%

### MetricsCollector

- Adapter: `sequential` (I/O)
- Processor: `concurrent` (CPU)

#### NullCircuit (baseline)
- Median: 2.2 ms
- P95: 2.84 ms
- P99: 3.14 ms
- CPU time: 2.14 ms (user: 1.53, sys: 0.61)
- RSS peak delta: +0 KB
- RSS avg delta: 0.2 KB/invocation
- Allocated: 885 objects
- Retained: 14 objects

#### Stoplight (circuit breaker)
- Median: 2.14 ms
- P95: 2.49 ms
- P99: 5.6 ms
- CPU time: 2.1 ms (user: 1.49, sys: 0.61)
- RSS before: 74716 KB
- RSS peak delta: +12 KB
- RSS avg delta: 1.4 KB/invocation
- GC objects/invocation: 1016
- Allocated: 885 objects
- Retained: 14 objects

#### Circuit Overhead
- Absolute: -0.06 ms
- Relative: -2.7%

### CatalogSearcher

- Adapter: `typhoeus` (I/O)
- Processor: `async` (CPU)

#### NullCircuit (baseline)
- Median: 1.78 ms
- P95: 2.28 ms
- P99: 2.29 ms
- CPU time: 1.75 ms (user: 1.24, sys: 0.51)
- RSS peak delta: +0 KB
- RSS avg delta: 0.2 KB/invocation
- Allocated: 878 objects
- Retained: 14 objects

#### Stoplight (circuit breaker)
- Median: 1.78 ms
- P95: 2.44 ms
- P99: 5.08 ms
- CPU time: 1.77 ms (user: 1.21, sys: 0.56)
- RSS before: 74468 KB
- RSS peak delta: +4 KB
- RSS avg delta: 0.8 KB/invocation
- GC objects/invocation: 1009
- Allocated: 878 objects
- Retained: 14 objects

#### Circuit Overhead
- Absolute: +0.0 ms
- Relative: +0.0%

### LogAggregator

- Adapter: `sequential` (I/O)
- Processor: `async` (CPU)

#### NullCircuit (baseline)
- Median: 2.11 ms
- P95: 3.74 ms
- P99: 6.49 ms
- CPU time: 2.06 ms (user: 1.47, sys: 0.59)
- RSS peak delta: +76 KB
- RSS avg delta: 17.2 KB/invocation
- Allocated: 894 objects
- Retained: 14 objects

#### Stoplight (circuit breaker)
- Median: 1.83 ms
- P95: 4.69 ms
- P99: 8.95 ms
- CPU time: 1.79 ms (user: 1.27, sys: 0.52)
- RSS before: 73384 KB
- RSS peak delta: +32 KB
- RSS avg delta: 8.8 KB/invocation
- GC objects/invocation: 1028
- Allocated: 894 objects
- Retained: 14 objects

#### Circuit Overhead
- Absolute: -0.28 ms
- Relative: -13.3%

### GeoResolver

- Adapter: `concurrent` (I/O)
- Processor: `async` (CPU)

#### NullCircuit (baseline)
- Median: 2.03 ms
- P95: 2.17 ms
- P99: 2.27 ms
- CPU time: 1.97 ms (user: 1.4, sys: 0.57)
- RSS peak delta: +0 KB
- RSS avg delta: 0.0 KB/invocation
- Allocated: 884 objects
- Retained: 14 objects

#### Stoplight (circuit breaker)
- Median: 2.01 ms
- P95: 2.48 ms
- P99: 5.6 ms
- CPU time: 2.0 ms (user: 1.42, sys: 0.58)
- RSS before: 75076 KB
- RSS peak delta: +0 KB
- RSS avg delta: 1.0 KB/invocation
- GC objects/invocation: 1015
- Allocated: 884 objects
- Retained: 14 objects

#### Circuit Overhead
- Absolute: -0.02 ms
- Relative: -1.0%

### HealthChecker

- Adapter: `async` (I/O)
- Processor: `async` (CPU)

#### NullCircuit (baseline)
- Median: 2.17 ms
- P95: 2.51 ms
- P99: 2.82 ms
- CPU time: 2.1 ms (user: 1.51, sys: 0.59)
- RSS peak delta: +4 KB
- RSS avg delta: 0.6 KB/invocation
- Allocated: 884 objects
- Retained: 14 objects

#### Stoplight (circuit breaker)
- Median: 2.09 ms
- P95: 2.42 ms
- P99: 5.53 ms
- CPU time: 2.01 ms (user: 1.41, sys: 0.6)
- RSS before: 75644 KB
- RSS peak delta: +0 KB
- RSS avg delta: 0.6 KB/invocation
- GC objects/invocation: 1015
- Allocated: 884 objects
- Retained: 14 objects

#### Circuit Overhead
- Absolute: -0.08 ms
- Relative: -3.7%

### DepGraphBuilder

- Adapter: `concurrent` (I/O)
- Processor: `sequential` (CPU)

#### NullCircuit (baseline)
- Median: 2.04 ms
- P95: 2.54 ms
- P99: 3.03 ms
- CPU time: 2.01 ms (user: 1.4, sys: 0.61)
- RSS peak delta: +0 KB
- RSS avg delta: 0.2 KB/invocation
- Allocated: 860 objects
- Retained: 14 objects

#### Stoplight (circuit breaker)
- Median: 1.94 ms
- P95: 4.4 ms
- P99: 5.53 ms
- CPU time: 1.92 ms (user: 1.34, sys: 0.58)
- RSS before: 75328 KB
- RSS peak delta: +0 KB
- RSS avg delta: 0.8 KB/invocation
- GC objects/invocation: 983
- Allocated: 860 objects
- Retained: 14 objects

#### Circuit Overhead
- Absolute: -0.1 ms
- Relative: -4.9%

### LegacyExporter

- Adapter: `typhoeus` (I/O)
- Processor: `sequential` (CPU)

#### NullCircuit (baseline)
- Median: 2.07 ms
- P95: 2.25 ms
- P99: 3.24 ms
- CPU time: 2.04 ms (user: 1.47, sys: 0.57)
- RSS peak delta: +0 KB
- RSS avg delta: 0.2 KB/invocation
- Allocated: 859 objects
- Retained: 14 objects

#### Stoplight (circuit breaker)
- Median: 1.97 ms
- P95: 3.1 ms
- P99: 5.53 ms
- CPU time: 1.92 ms (user: 1.38, sys: 0.54)
- RSS before: 75100 KB
- RSS peak delta: +4 KB
- RSS avg delta: 0.6 KB/invocation
- GC objects/invocation: 982
- Allocated: 859 objects
- Retained: 14 objects

#### Circuit Overhead
- Absolute: -0.1 ms
- Relative: -4.8%

### ConfigSnapshot

- Adapter: `async` (I/O)
- Processor: `sequential` (CPU)

#### NullCircuit (baseline)
- Median: 2.05 ms
- P95: 2.29 ms
- P99: 3.02 ms
- CPU time: 2.03 ms (user: 1.45, sys: 0.58)
- RSS peak delta: +0 KB
- RSS avg delta: 0.0 KB/invocation
- Allocated: 858 objects
- Retained: 14 objects

#### Stoplight (circuit breaker)
- Median: 2.06 ms
- P95: 5.58 ms
- P99: 5.96 ms
- CPU time: 2.03 ms (user: 1.45, sys: 0.58)
- RSS before: 75352 KB
- RSS peak delta: +24 KB
- RSS avg delta: 6.0 KB/invocation
- GC objects/invocation: 981
- Allocated: 858 objects
- Retained: 14 objects

#### Circuit Overhead
- Absolute: +0.01 ms
- Relative: +0.5%

### ReportGenerator

- Adapter: `sequential` (I/O)
- Processor: `sequential` (CPU)

#### NullCircuit (baseline)
- Median: 2.0 ms
- P95: 3.14 ms
- P99: 4.16 ms
- CPU time: 1.98 ms (user: 1.41, sys: 0.57)
- RSS peak delta: +24 KB
- RSS avg delta: 6.6 KB/invocation
- Allocated: 857 objects
- Retained: 14 objects

#### Stoplight (circuit breaker)
- Median: 2.17 ms
- P95: 2.39 ms
- P99: 5.96 ms
- CPU time: 2.1 ms (user: 1.45, sys: 0.65)
- RSS before: 75252 KB
- RSS peak delta: +0 KB
- RSS avg delta: 3.6 KB/invocation
- GC objects/invocation: 980
- Allocated: 857 objects
- Retained: 14 objects

#### Circuit Overhead
- Absolute: +0.17 ms
- Relative: +8.5%

### FeedIngestor

- Adapter: `async` (I/O)
- Processor: `ractor` (CPU)

#### NullCircuit (baseline)
- Median: 1.82 ms
- P95: 2.47 ms
- P99: 3.34 ms
- CPU time: 1.85 ms (user: 1.3, sys: 0.55)
- RSS peak delta: +4 KB
- RSS avg delta: 1.0 KB/invocation
- Allocated: 882 objects
- Retained: 14 objects

#### Stoplight (circuit breaker)
- Median: 1.94 ms
- P95: 3.97 ms
- P99: 5.63 ms
- CPU time: 1.93 ms (user: 1.38, sys: 0.55)
- RSS before: 74520 KB
- RSS peak delta: +0 KB
- RSS avg delta: 0.6 KB/invocation
- GC objects/invocation: 1013
- Allocated: 882 objects
- Retained: 14 objects

#### Circuit Overhead
- Absolute: +0.12 ms
- Relative: +6.6%

### OrderFulfiller

- Adapter: `typhoeus` (I/O)
- Processor: `ractor` (CPU)

#### NullCircuit (baseline)
- Median: 2.04 ms
- P95: 2.32 ms
- P99: 3.15 ms
- CPU time: 1.99 ms (user: 1.41, sys: 0.58)
- RSS peak delta: +8 KB
- RSS avg delta: 4.2 KB/invocation
- Allocated: 878 objects
- Retained: 14 objects

#### Stoplight (circuit breaker)
- Median: 2.02 ms
- P95: 2.7 ms
- P99: 5.49 ms
- CPU time: 1.99 ms (user: 1.41, sys: 0.58)
- RSS before: 74020 KB
- RSS peak delta: +16 KB
- RSS avg delta: 4.6 KB/invocation
- GC objects/invocation: 1009
- Allocated: 878 objects
- Retained: 14 objects

#### Circuit Overhead
- Absolute: -0.02 ms
- Relative: -1.0%

### UserEnricher

- Adapter: `sequential` (I/O)
- Processor: `ractor` (CPU)

#### NullCircuit (baseline)
- Median: 2.03 ms
- P95: 2.43 ms
- P99: 2.57 ms
- CPU time: 2.0 ms (user: 1.43, sys: 0.57)
- RSS peak delta: +0 KB
- RSS avg delta: 0.0 KB/invocation
- Allocated: 884 objects
- Retained: 14 objects

#### Stoplight (circuit breaker)
- Median: 2.1 ms
- P95: 4.09 ms
- P99: 5.47 ms
- CPU time: 2.05 ms (user: 1.47, sys: 0.58)
- RSS before: 74824 KB
- RSS peak delta: +80 KB
- RSS avg delta: 12.6 KB/invocation
- GC objects/invocation: 1015
- Allocated: 884 objects
- Retained: 14 objects

#### Circuit Overhead
- Absolute: +0.07 ms
- Relative: +3.4%

### ThreatScanner

- Adapter: `concurrent` (I/O)
- Processor: `ractor` (CPU)

#### NullCircuit (baseline)
- Median: 1.99 ms
- P95: 2.23 ms
- P99: 2.67 ms
- CPU time: 1.96 ms (user: 1.4, sys: 0.56)
- RSS peak delta: +0 KB
- RSS avg delta: 0.0 KB/invocation
- Allocated: 884 objects
- Retained: 14 objects

#### Stoplight (circuit breaker)
- Median: 2.13 ms
- P95: 2.81 ms
- P99: 5.86 ms
- CPU time: 2.13 ms (user: 1.5, sys: 0.63)
- RSS before: 74592 KB
- RSS peak delta: +16 KB
- RSS avg delta: 5.4 KB/invocation
- GC objects/invocation: 1015
- Allocated: 884 objects
- Retained: 14 objects

#### Circuit Overhead
- Absolute: +0.14 ms
- Relative: +7.0%

## Methodology

1. Global warmup: 3 invocations with throwaway clients to
   warm JIT and server (excluded from metrics)
2. All 16 clients pre-warmed (both NullCircuit and Stoplight
   variants) — connections established before any measurement
3. Examples run in randomized order to avoid bias
4. Each example runs NullCircuit baseline first, then
   Stoplight circuit breaker (back-to-back for thermal
   consistency)
5. 20 timed invocations measure steady-state
   performance with connection reuse — median, P95, P99 reported
6. Connection establishment overhead (TCP handshake, TLS)
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
