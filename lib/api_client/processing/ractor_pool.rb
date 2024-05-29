require_relative "../transforms"

module ApiClient
  module Processing
    # Fixed-size Ractor pool for parallel CPU-bound work
    #
    # Uses Ractor::Port for bidirectional communication (Ruby 4.0+ only).
    # On Ruby 3.4, Ractor is experimental and Ractor::Port is unavailable —
    # this class will raise NameError if instantiated on < 4.0.
    # Workers loop waiting for work, process, and send results back via port.
    #
    # == Coverage measurement artifact
    #
    # SimpleCov/Coverage reports ~87% for this file. This is a measurement
    # artifact, not a real coverage gap. Code inside Ractor.new { } blocks
    # (the worker loop in create_worker) runs in isolated per-ractor memory
    # that Coverage cannot instrument — only the main Ractor is tracked.
    # Unlike fork, there is no at_fork equivalent for Ractors.
    # All paths are exercised via the public API (process, shutdown) —
    # verify via spec/lib/api_client/processing/ractor_pool_spec.rb.
    #
    # @example Direct usage
    #   pool = RactorPool.new(size: 4)
    #   results, errors = pool.process(items, extractor: ->(i) { i }, transform: :json)
    #   pool.shutdown
    #
    class RactorPool
      attr_reader :size

      # Transforms inlined in Ractor workers (isolated memory prevents
      # access to Transforms::REGISTRY). This set must match
      # Transforms::REGISTRY.keys — validated at class load time below.
      RACTOR_TRANSFORMS = %i[identity json sha256].freeze

      # @param size [Integer] Number of workers (default: CPU count)
      def initialize(size: Etc.nprocessors)
        @size = size
        @workers = []
        @mutex = Mutex.new
        @shutdown = false
        @started = false
      end

      # Process items in parallel using worker pool
      # @param items [Array] Items to process
      # @param extractor [Proc] Extracts shareable data from item
      # @param transform [Symbol] Built-in transform to apply in Ractor
      # @return [Array<results, errors>] Processed results and errors
      def process(items, extractor:, transform: :identity)
        raise ArgumentError, I18n.t("transforms.unknown", transform: transform) unless Transforms.valid?(transform)

        ensure_started
        return [[], []] if items.empty?

        # Extract shareable data in main Ractor using Ractor.make_shareable
        work_items = items.map.with_index do |item, index|
          data = extractor.call(item)
          shareable_data = Ractor.make_shareable(data)
          [index, shareable_data, transform]
        end

        # Distribute work and collect results
        dispatch_and_collect(work_items)
      end

      # Shutdown pool and terminate workers
      def shutdown
        @mutex.synchronize do
          return if @shutdown
          @shutdown = true

          @workers.each do |worker|
            worker[:ractor].send(:shutdown)
          rescue
            nil
          end
          @workers.clear
        end
      end

      # Check if pool is running
      def running?
        @started && !@shutdown
      end

      # Current worker count
      def worker_count
        @mutex.synchronize { @workers.size }
      end

      private

      def ensure_started
        @mutex.synchronize do
          return if @started
          raise I18n.t("processing.pool_shutdown") if @shutdown

          @size.times { @workers << create_worker }
          @started = true
        end
      end

      def create_worker
        # Create a port for this worker to send results back
        result_port = Ractor::Port.new

        # Coverage artifact: the block below executes in an isolated Ractor.
        # Coverage module only instruments the main Ractor — this code IS
        # exercised by specs but will always show as uncovered.
        ractor = Ractor.new(result_port) do |port|
          loop do
            msg = Ractor.receive
            break if msg == :shutdown

            index, data, transform = msg
            begin
              # Transform logic inlined — Ractors have isolated memory
              # and cannot access the parent's Transforms::REGISTRY.
              # Must stay in sync with RACTOR_TRANSFORMS (validated at load time).
              result = case transform
              when :identity then data
              when :json then JSON.parse(data)
              when :sha256 then Digest::SHA256.hexdigest(data)
              else raise ArgumentError, "Unknown transform: #{transform}"
              end
              port << [index, :ok, result]
            rescue => error
              port << [index, :error, error.class.name, error.message]
            end
          end
        end

        {ractor: ractor, port: result_port}
      end

      def dispatch_and_collect(work_items)
        total = work_items.size
        results = Array.new(total)
        errors = []
        port_to_worker = build_port_index
        ports = port_to_worker.keys

        next_work_index = send_initial_batch(work_items)
        pending = total

        while pending > 0
          port, result = Ractor.select(*ports)
          pending -= 1

          record_result(result, results, errors)
          next_work_index = dispatch_next(work_items, next_work_index, port_to_worker[port])
        end

        [results, errors]
      end

      def build_port_index
        @workers.each_with_object({}) { |worker, idx| idx[worker[:port]] = worker }
      end

      def send_initial_batch(work_items)
        worker_count = @workers.size
        work_items.each_with_index do |work, idx|
          break idx if idx >= worker_count
          @workers[idx][:ractor].send(work)
        end
        [work_items.size, worker_count].min
      end

      def record_result(result, results, errors)
        index, status, *payload = result
        if status == :ok
          results[index] = payload.first
        else
          error_class, error_message = payload
          errors << {index: index, error_class: error_class, message: error_message}
        end
      end

      def dispatch_next(work_items, next_index, worker)
        return next_index if next_index >= work_items.size

        worker[:ractor].send(work_items[next_index])
        next_index + 1
      end
    end

    # Load-time validation: ensure inlined Ractor transforms stay in sync
    # with Transforms::REGISTRY. Catches divergence immediately rather than
    # at runtime when a new transform is used with RactorPool.
    unless RactorPool::RACTOR_TRANSFORMS.sort == Transforms::REGISTRY.keys.sort
      missing = Transforms::REGISTRY.keys - RactorPool::RACTOR_TRANSFORMS
      extra = RactorPool::RACTOR_TRANSFORMS - Transforms::REGISTRY.keys
      raise LoadError,
        "RactorPool::RACTOR_TRANSFORMS out of sync with Transforms::REGISTRY. " \
        "Missing: #{missing.inspect}, Extra: #{extra.inspect}. " \
        "Update the case statement in RactorPool#create_worker."
    end
  end
end
