# frozen_string_literal: true

require "socket"

module Support
  module Chaos
    class HttpUpstream
      attr_reader :port

      def start
        @server = TCPServer.new("127.0.0.1", 0)
        @port = @server.addr[1]
        @thread = Thread.new { serve } # standard:disable ThreadSafety/NewThread -- isolated upstream for explicit network tests
        self
      end

      def stop
        @server&.close
        @thread&.join(2)
        @server = nil
        @thread = nil
      end

      def address
        "127.0.0.1:#{port}"
      end

      private

      def serve
        loop do
          client = @server.accept
          handle(client)
        end
      rescue IOError, Errno::EBADF
        nil
      end

      def handle(client)
        client.gets
        while (line = client.gets)
          break if line == "\r\n" || line == "\n"
        end

        body = '{"status":"ok"}'
        client.write(
          "HTTP/1.1 200 OK\r\n" \
          "content-type: application/json\r\n" \
          "content-length: #{body.bytesize}\r\n" \
          "connection: close\r\n\r\n#{body}"
        )
      rescue IOError, Errno::EPIPE, Errno::ECONNRESET
        nil
      ensure
        client&.close
      end
    end
  end
end
