namespace :examples do
  desc "Collect per-client metrics for all 16 example clients and write doc/example-metrics.md"
  task :metrics do
    Warning[:experimental] = false
    require_relative "../../lib/api_client"
    require "async/http/endpoint"
    require_relative "../../spec/support/test_server/server"

    memory_profiler_available = begin
      require "memory_profiler"
      true
    rescue LoadError
      false
    end

    iterations = Integer(ENV.fetch("METRICS_ITERATIONS", 20))

    # Nearest-rank percentile (matches numpy default)
    percentile = ->(sorted, pct) {
      return sorted.first if sorted.size == 1
      rank = (pct / 100.0 * sorted.size).ceil - 1
      sorted[[rank, 0].max]
    }

    examples = {
      "OrderFulfiller" => {
        klass: ApiClient::Examples::OrderFulfiller,
        invoke: ->(c) { c.fulfill_orders(order_id: "ORD-9001") },
        adapter: :typhoeus, processor: :ractor
      },
      "CatalogSearcher" => {
        klass: ApiClient::Examples::CatalogSearcher,
        invoke: ->(c) { c.search(query: "ruby book") },
        adapter: :typhoeus, processor: :async
      },
      "ComplianceAuditor" => {
        klass: ApiClient::Examples::ComplianceAuditor,
        invoke: ->(c) { c.build_report(tenant_id: "T-100") },
        adapter: :typhoeus, processor: :concurrent
      },
      "LegacyExporter" => {
        klass: ApiClient::Examples::LegacyExporter,
        invoke: ->(c) { c.export(resource: "customers") },
        adapter: :typhoeus, processor: :sequential
      },
      "FeedIngestor" => {
        klass: ApiClient::Examples::FeedIngestor,
        invoke: ->(c) { c.ingest(feed_id: "FEED-42") },
        adapter: :async, processor: :ractor
      },
      "HealthChecker" => {
        klass: ApiClient::Examples::HealthChecker,
        invoke: ->(c) { c.check(cluster: "us-east-1") },
        adapter: :async, processor: :async
      },
      "NotifyDispatcher" => {
        klass: ApiClient::Examples::NotifyDispatcher,
        invoke: ->(c) { c.dispatch(campaign_id: "CAMP-77") },
        adapter: :async, processor: :concurrent
      },
      "ConfigSnapshot" => {
        klass: ApiClient::Examples::ConfigSnapshot,
        invoke: ->(c) { c.snapshot(app: "billing-service") },
        adapter: :async, processor: :sequential
      },
      "ThreatScanner" => {
        klass: ApiClient::Examples::ThreatScanner,
        invoke: ->(c) { c.scan(indicator_id: "IOC-8842") },
        adapter: :concurrent, processor: :ractor
      },
      "GeoResolver" => {
        klass: ApiClient::Examples::GeoResolver,
        invoke: ->(c) { c.resolve(domain: "cdn.example.com") },
        adapter: :concurrent, processor: :async
      },
      "PayReconciler" => {
        klass: ApiClient::Examples::PayReconciler,
        invoke: ->(c) { c.reconcile(batch_id: "BATCH-2024-01") },
        adapter: :concurrent, processor: :concurrent
      },
      "DepGraphBuilder" => {
        klass: ApiClient::Examples::DepGraphBuilder,
        invoke: ->(c) { c.build_graph(package: "api_client") },
        adapter: :concurrent, processor: :sequential
      },
      "UserEnricher" => {
        klass: ApiClient::Examples::UserEnricher,
        invoke: ->(c) { c.enrich(segment_id: "SEG-500") },
        adapter: :sequential, processor: :ractor
      },
      "LogAggregator" => {
        klass: ApiClient::Examples::LogAggregator,
        invoke: ->(c) { c.aggregate(service: "api-gateway", window: "1h") },
        adapter: :sequential, processor: :async
      },
      "MetricsCollector" => {
        klass: ApiClient::Examples::MetricsCollector,
        invoke: ->(c) { c.collect_metrics(namespace: "production") },
        adapter: :sequential, processor: :concurrent
      },
      "ReportGenerator" => {
        klass: ApiClient::Examples::ReportGenerator,
        invoke: ->(c) { c.generate(report_type: "monthly-summary") },
        adapter: :sequential, processor: :sequential
      }
    }.freeze

    rss_kb = -> { ApiClient::SystemInfo.rss_kb }

    # Build and warm a client: instantiate + one invocation to establish connection
    build_warm_client = lambda do |entry, base_url, circuit_enabled: true|
      client_opts = {service_uri: base_url}
      client_opts[:circuit] = {enabled: false} unless circuit_enabled
      client = entry[:klass].new(**client_opts)
      entry[:invoke].call(client) # establish connection
      client
    end

    collect_metrics = lambda do |name, entry, client|
      wall_times = []
      cpu_times = []
      per_iter_rss = []

      iterations.times do
        # Double GC pass + compact stabilizes RSS on macOS where
        # compaction triggers CoW page faults that inflate resident_size.
        # The second pass reclaims pages dirtied by the first compact.
        GC.start(full_mark: true, immediate_sweep: true)
        GC.compact if GC.respond_to?(:compact)
        GC.start(full_mark: true, immediate_sweep: true)

        rss_before = rss_kb.call
        gc_before = GC.stat(:total_allocated_objects)
        cpu_before = Process.times
        wall_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        entry[:invoke].call(client)

        wall_elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - wall_start
        cpu_after = Process.times
        gc_after = GC.stat(:total_allocated_objects)
        rss_after = rss_kb.call

        wall_times << (wall_elapsed * 1000).round(2)
        user_ms = ((cpu_after.utime - cpu_before.utime) * 1000).round(2)
        sys_ms = ((cpu_after.stime - cpu_before.stime) * 1000).round(2)
        cpu_times << {user_ms: user_ms, sys_ms: sys_ms, total_ms: (user_ms + sys_ms).round(2)}
        per_iter_rss << {before: rss_before, after: rss_after, gc_alloc: gc_after - gc_before}
      end

      wall_sorted = wall_times.sort
      cpu_sorted = cpu_times.sort_by { |c| c[:total_ms] }

      # RSS: use per-iteration deltas to avoid masking by GC
      rss_deltas = per_iter_rss.map { |r| r[:after] - r[:before] }
      # P95 of deltas filters single-iteration outliers (CoW faults,
      # lazy page mapping) that inflate max but don't reflect steady state
      sorted_deltas = rss_deltas.sort
      peak_delta_kb = percentile.call(sorted_deltas, 95)
      # Use GC allocated objects as proxy when RSS shows 0
      gc_allocs_per_iter = per_iter_rss.map { |r| r[:gc_alloc] }
      median_gc_alloc = gc_allocs_per_iter.sort[gc_allocs_per_iter.size / 2]

      # Compute avg RSS delta from already-collected per-iteration data
      mem_delta_kb = rss_deltas.sum.to_f / rss_deltas.size

      alloc_count = nil
      retained_count = nil
      if memory_profiler_available
        report = MemoryProfiler.report { entry[:invoke].call(client) }
        alloc_count = report.total_allocated
        retained_count = report.total_retained
      end

      median_cpu = cpu_sorted[cpu_sorted.size / 2]

      {
        name: name, adapter: entry[:adapter], processor: entry[:processor],
        median_ms: wall_sorted[wall_sorted.size / 2],
        p95_ms: percentile.call(wall_sorted, 95),
        p99_ms: percentile.call(wall_sorted, 99),
        cpu_user_ms: median_cpu[:user_ms],
        cpu_sys_ms: median_cpu[:sys_ms],
        cpu_total_ms: median_cpu[:total_ms],
        mem_delta_kb: mem_delta_kb.round(1),
        peak_delta_kb: peak_delta_kb,
        gc_alloc_per_iter: median_gc_alloc,
        rss_before_kb: per_iter_rss.first[:before],
        allocated_objects: alloc_count, retained_objects: retained_count
      }
    end

    # Silence Async::Container logging
    require "console"
    Console.logger.off!

    puts "Starting Falcon test server..."
    server = Support::TestServer.new.start
    base_url = server.base_url
    puts "Server ready at #{base_url} (#{server.worker_count} workers)"

    # Redirect stderr after server startup to suppress Falcon warnings
    # during benchmark iterations (restore in ensure block)
    original_stderr = $stderr
    $stderr = File.open(File::NULL, "w")

    begin
      # Global warmup: run one example to warm JIT and server
      # Use a throwaway client to avoid connection pooling affecting measurements
      puts "Warming up (JIT and server)..."
      warmup_example = examples.first
      3.times do
        warmup_client = warmup_example[1][:klass].new(
          service_uri: base_url, circuit: {enabled: false}
        )
        warmup_example[1][:invoke].call(warmup_client)
      end
      puts "  JIT and test server warmed"

      # Randomize example order for unbiased measurement
      randomized_examples = examples.to_a.shuffle

      # Pre-warm ALL clients (both circuit variants) so no client pays
      # first-connection cost during measurement
      puts "Warming up #{randomized_examples.size} clients (NullCircuit + Stoplight)..."
      warmed_clients = {}
      randomized_examples.each do |name, entry|
        warmed_clients[name] = {
          null: build_warm_client.call(entry, base_url, circuit_enabled: false),
          stoplight: build_warm_client.call(entry, base_url)
        }
      end
      puts "  All clients warm\nProfiling clients..."

      all_metrics = []
      null_circuit_metrics = []

      randomized_examples.each do |name, entry|
        # Run NullCircuit baseline first for each example
        print "  #{name} (NullCircuit)..."
        nc = collect_metrics.call(name, entry, warmed_clients[name][:null])
        nc[:circuit] = :null
        puts " #{nc[:median_ms]} ms (cpu: #{nc[:cpu_total_ms]} ms)"
        null_circuit_metrics << nc

        # Then run with Stoplight circuit breaker
        print "  #{name} (Stoplight)..."
        m = collect_metrics.call(name, entry, warmed_clients[name][:stoplight])
        puts " #{m[:median_ms]} ms (cpu: #{m[:cpu_total_ms]} ms, rss: +#{m[:peak_delta_kb]} KB peak)"
        all_metrics << m
      end

      # Merge NullCircuit and Stoplight metrics, sort by Stoplight performance
      merged_metrics = []
      all_metrics.each do |sl|
        nc = null_circuit_metrics.find { |m| m[:name] == sl[:name] }
        merged_metrics << {stoplight: sl, null_circuit: nc}
      end
      merged_metrics.sort_by! { |pair| pair[:stoplight][:median_ms] }

      has_alloc = all_metrics.any? { |m| m[:allocated_objects] }
      yjit = defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled?
      date = Time.now.strftime("%Y-%m-%d")
      workers = server.worker_count

      lines = []

      # Header
      lines.push(
        "---",
        'title: "Example Client Metrics"',
        'audience_chain: ["developer", "maintainer"]',
        'semantic_version: "1.0"',
        "last_updated_at: \"#{date}\"",
        "---",
        "",
        "## Example Clients Metrics",
        "",
        "Performance metrics for the 16 canonical `RequestFlow`",
        "examples, measured against a custom Falcon test server on",
        "localhost.",
        "",
        "Regenerate with:",
        "",
        "```sh",
        "bundle exec rake examples:metrics",
        "```",
        "",
        "Each client executes its full pipeline",
        "(fetch → then → fan_out → map → collect) #{iterations} times.",
        "Timing is the median wall-clock run. Memory and allocation",
        "counts are per single invocation.",
        "",
        "Each example runs NullCircuit baseline first (circuit disabled),",
        "then Stoplight circuit breaker. Tables show both measurements",
        "with NullCircuit as the first row.",
        "",
        "## Environment",
        "",
        "```text",
        "Ruby:    #{RUBY_VERSION} (#{RUBY_PLATFORM})",
        "YJIT:    #{yjit ? "enabled" : "disabled"}",
        "Server:  Falcon (Async::Container::Threaded, #{workers} workers)",
        "Network: loopback (127.0.0.1)",
        "```",
        ""
      )

      # Summary tables — grouped by processor
      lines.push("## Processor x Adapter Matrix", "")
      lines.push(
        "Grouped by processor (fastest to slowest). Within each group,",
        "clients sorted by Stoplight performance (fastest first).",
        "NullCircuit baseline shown first for each client.",
        ""
      )

      # Calculate average performance per processor to order groups
      processor_avg = {}
      processor_order = %i[ractor async concurrent sequential]
      processor_order.each do |processor|
        group = merged_metrics.select { |pair| pair[:stoplight][:processor] == processor }
        next if group.empty?
        avg = group.sum { |pair| pair[:stoplight][:median_ms] } / group.size.to_f
        processor_avg[processor] = avg
      end

      # Sort processors by average performance (fastest first)
      sorted_processors = processor_avg.sort_by { |_proc, avg| avg }.map(&:first)

      sorted_processors.each do |processor|
        group = merged_metrics.select { |pair| pair[:stoplight][:processor] == processor }
        next if group.empty?

        lines.push("### #{processor}", "")

        # Sort by Stoplight median within each processor group (fastest first)
        group.sort_by! { |pair| pair[:stoplight][:median_ms] }

        if has_alloc
          lines << "| Client            | Circuit     | Adapter    | Med ms | CPU ms | Alloc | Retain |"
          lines << "| ----------------- | ----------- | ---------- | -----: | -----: | ----: | -----: |"
        else
          lines << "| Client            | Circuit     | Adapter    | Med ms | CPU ms |"
          lines << "| ----------------- | ----------- | ---------- | -----: | -----: |"
        end

        group.each do |pair|
          # NullCircuit first, then Stoplight (tightly bounded)
          [pair[:null_circuit], pair[:stoplight]].each do |m|
            next unless m
            circuit_label = (m[:circuit] == :null) ? "NullCircuit" : "Stoplight"
            lines << if has_alloc
              "| %-17s | %-11s | %-10s | %6s | %6s | %5s | %6s |" % [
                m[:name], circuit_label, m[:adapter],
                m[:median_ms], m[:cpu_total_ms],
                m[:allocated_objects] || "n/a",
                m[:retained_objects] || "n/a"
              ]
            else
              "| %-17s | %-11s | %-10s | %6s | %6s |" % [
                m[:name], circuit_label, m[:adapter],
                m[:median_ms], m[:cpu_total_ms]
              ]
            end
          end
        end
        lines << ""
      end

      # Per-client detail — ordered by processor group then Stoplight
      # median within group (matches summary table ordering)
      lines.push("## Per-Client Detail", "")

      sorted_processors.each do |processor|
        group = merged_metrics.select { |pair| pair[:stoplight][:processor] == processor }
        next if group.empty?
        group.sort_by! { |pair| pair[:stoplight][:median_ms] }

        group.each do |pair|
          sl = pair[:stoplight]
          nc = pair[:null_circuit]

          lines.push("### #{sl[:name]}", "")
          lines << "- Adapter: `#{sl[:adapter]}` (I/O)"
          lines << "- Processor: `#{sl[:processor]}` (CPU)"
          lines << ""
          lines << "#### NullCircuit (baseline)"
          lines << "- Median: #{nc[:median_ms]} ms"
          lines << "- P95: #{nc[:p95_ms]} ms"
          lines << "- P99: #{nc[:p99_ms]} ms"
          lines << "- CPU time: #{nc[:cpu_total_ms]} ms (user: #{nc[:cpu_user_ms]}, sys: #{nc[:cpu_sys_ms]})"
          lines << "- RSS peak delta: +#{nc[:peak_delta_kb]} KB"
          lines << "- RSS avg delta: #{nc[:mem_delta_kb]} KB/invocation"
          if has_alloc && nc[:allocated_objects]
            lines << "- Allocated: #{nc[:allocated_objects]} objects"
            lines << "- Retained: #{nc[:retained_objects]} objects"
          end
          lines << ""
          lines << "#### Stoplight (circuit breaker)"
          lines << "- Median: #{sl[:median_ms]} ms"
          lines << "- P95: #{sl[:p95_ms]} ms"
          lines << "- P99: #{sl[:p99_ms]} ms"
          lines << "- CPU time: #{sl[:cpu_total_ms]} ms (user: #{sl[:cpu_user_ms]}, sys: #{sl[:cpu_sys_ms]})"
          lines << "- RSS before: #{sl[:rss_before_kb]} KB"
          lines << "- RSS peak delta: +#{sl[:peak_delta_kb]} KB"
          lines << "- RSS avg delta: #{sl[:mem_delta_kb]} KB/invocation"
          lines << "- GC objects/invocation: #{sl[:gc_alloc_per_iter]}"
          if has_alloc && sl[:allocated_objects]
            lines << "- Allocated: #{sl[:allocated_objects]} objects"
            lines << "- Retained: #{sl[:retained_objects]} objects"
          end

          # Calculate overhead
          overhead_ms = (sl[:median_ms] - nc[:median_ms]).round(2)
          overhead_pct = ((overhead_ms / nc[:median_ms]) * 100).round(1)
          sign = (overhead_ms >= 0) ? "+" : ""
          lines << ""
          lines << "#### Circuit Overhead"
          lines << "- Absolute: #{sign}#{overhead_ms} ms"
          lines << "- Relative: #{sign}#{overhead_pct}%"
          lines << ""
        end
      end

      # Footer
      lines.push(
        "## Methodology", "",
        "1. Global warmup: 3 invocations with throwaway clients to",
        "   warm JIT and server (excluded from metrics)",
        "2. All 16 clients pre-warmed (both NullCircuit and Stoplight",
        "   variants) — connections established before any measurement",
        "3. Examples run in randomized order to avoid bias",
        "4. Each example runs NullCircuit baseline first, then",
        "   Stoplight circuit breaker (back-to-back for thermal",
        "   consistency)",
        "5. #{iterations} timed invocations measure steady-state",
        "   performance with connection reuse — median, P95, P99 reported",
        "6. Connection establishment overhead (TCP handshake, TLS)",
        "   is absorbed during pre-warm, excluded from metrics",
        "7. CPU time: `Process.times` user+system delta per",
        "   invocation (median reported)",
        "8. P95/P99: nearest-rank percentile over wall-clock times",
        "   — filters single-iteration outliers (GC, CoW faults)",
        "9. RSS peak delta: P95 of per-iteration RSS deltas",
        "   (filters single-iteration outliers from CoW faults,",
        "   lazy page mapping, or GC compaction artifacts)",
        "10. RSS avg delta: mean of per-iteration deltas",
        "    reported as float to surface sub-KB changes",
        "11. RSS stabilization: double GC pass (start + compact +",
        "    start) before each iteration — second pass reclaims",
        "    pages dirtied by compaction on macOS",
        "12. GC objects/invocation: `GC.stat(:total_allocated_objects)`",
        "    delta per iteration (median), independent of RSS",
        "13. Allocations: `memory_profiler` single-invocation report",
        "    (if available)",
        "14. NullCircuit: `circuit_config.enabled = false` forces",
        "    `NullCircuit` (pass-through `yield`) — no state machine,",
        "    no failure tracking, no mutex synchronization",
        "15. Circuit Overhead: Stoplight median - NullCircuit median",
        "16. Tables grouped by processor, sorted by Stoplight median",
        "    latency within each group (fastest first)",
        "",
        "## See Also", "",
        "- [Examples README](../lib/api_client/examples/README.md)",
        "- [Architecture](architecture.md)",
        "- [Circuit Breaker](circuit-breaker.md)",
        "- [Profiling](../lib/api_client/profiling.rb)",
        ""
      )

      doc_path = File.expand_path("doc/example-metrics.md", __dir__.then { |d| File.expand_path("../..", d) })
      File.write(doc_path, lines.join("\n"))
      puts "\nWrote #{doc_path} (#{all_metrics.size} clients, #{null_circuit_metrics.size} NullCircuit baselines)"
    ensure
      server.stop
      $stderr.close unless $stderr == original_stderr
      $stderr = original_stderr
    end
  end
end
