# frozen_string_literal: true

require "socket"
require_relative "health_app"

module Support
  module ServerCompat
    class PumaServer
      attr_reader :port

      def start
        require "puma"
        require "puma/configuration"
        require "puma/launcher"
        require "puma/log_writer"

        @port = available_port
        configuration = Puma::Configuration.new do |config|
          config.bind "tcp://127.0.0.1:#{port}"
          config.threads 1, 2
          config.log_requests false
          config.quiet true
          config.app HealthApp.new
        end

        @launcher = Puma::Launcher.new(configuration, log_writer: Puma::LogWriter.null)
        @thread = Thread.new { @launcher.run } # standard:disable ThreadSafety/NewThread -- the server must run beside the spec client
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

      def base_url
        "http://127.0.0.1:#{port}"
      end

      private

      def available_port
        socket = TCPServer.new("127.0.0.1", 0)
        socket.addr[1]
      ensure
        socket&.close
      end

      def wait_for_server
        100.times do
          socket = TCPSocket.new("127.0.0.1", port)
          socket.close
          return
        rescue Errno::ECONNREFUSED
          raise "Puma compatibility fixture exited before binding" unless @thread&.alive?

          sleep 0.05
        end

        raise "Puma compatibility fixture failed to start on 127.0.0.1:#{port}"
      end
    end
  end
end
