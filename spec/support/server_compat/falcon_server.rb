# frozen_string_literal: true

require "socket"
require_relative "health_app"

module Support
  module ServerCompat
    class FalconServer
      attr_reader :port

      def start
        require "falcon/rackup/handler"

        @port = available_port
        @ready = Queue.new
        @thread = Thread.new do # standard:disable ThreadSafety/NewThread -- the server must run beside the spec client
          Falcon::Rackup::Handler.run(HealthApp.new, Host: "127.0.0.1", Port: port) do |handler|
            @ready << handler
          end
        end

        @handler = @ready.pop(timeout: 5)
        unless @handler
          @thread.value if @thread&.stop?
          raise "Falcon compatibility fixture failed to start on 127.0.0.1:#{port}"
        end

        self
      rescue
        stop
        raise
      end

      def stop
        @handler&.stop
        @thread&.join(2)
        @handler = nil
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
    end
  end
end
