require "socket"
require_relative "router"

module Support
  class MockApi
    class BenchmarkServer
      attr_reader :port

      def initialize
        @port = available_port
        @router = Router.new
      end

      def start
        require "puma"
        require "puma/configuration"
        require "puma/launcher"
        require "rack"

        app = ->(env) { @router.call(Rack::Request.new(env)) }
        configuration = Puma::Configuration.new do |config|
          config.bind "tcp://127.0.0.1:#{port}"
          config.threads 2, 4
          config.log_requests false
          config.quiet true
          config.app app
        end

        @launcher = Puma::Launcher.new(configuration)
        @thread = Thread.new { @launcher.run } # standard:disable ThreadSafety/NewThread -- benchmark server runs separately from measured work
        wait_for_server
        self
      rescue
        stop
        raise
      end

      def stop
        @launcher&.stop
        @thread&.join(2)
        @launcher = nil
        @thread = nil
      end

      def base_url = "http://127.0.0.1:#{port}"

      private

      def available_port
        server = TCPServer.new("127.0.0.1", 0)
        server.addr[1]
      ensure
        server&.close
      end

      def wait_for_server
        20.times do
          socket = TCPSocket.new("127.0.0.1", port)
          socket.close
          return
        rescue Errno::ECONNREFUSED
          sleep 0.05
        end

        raise "Benchmark fixture server failed to start on port #{port}"
      end
    end
  end
end
