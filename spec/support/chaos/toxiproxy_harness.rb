# frozen_string_literal: true

require_relative "http_upstream"

module Support
  module Chaos
    class ToxiproxyHarness
      attr_reader :proxy, :proxy_port

      def start
        require "toxiproxy"
        raise_unless_toxiproxy_is_running

        @upstream = HttpUpstream.new.start
        @proxy_name = "api_client_#{Process.pid}_#{SecureRandom.hex(4)}"
        @proxy_port = available_port
        Toxiproxy.populate([
          {
            name: @proxy_name,
            listen: "127.0.0.1:#{proxy_port}",
            upstream: @upstream.address
          }
        ])
        @proxy = Toxiproxy[@proxy_name]
        self
      end

      def stop
        proxy&.destroy
      ensure
        @upstream&.stop
      end

      def base_url
        "http://127.0.0.1:#{proxy_port}"
      end

      private

      def raise_unless_toxiproxy_is_running
        raise Toxiproxy::NotFound, "control API is not listening" unless Toxiproxy.running?

        Toxiproxy.version
      rescue Errno::ECONNREFUSED, Toxiproxy::NotFound => error
        raise "Toxiproxy is required for --tag chaos. Start it with `toxiproxy-server` (control API: 127.0.0.1:8474): #{error.message}", cause: error
      end

      def available_port
        socket = TCPServer.new("127.0.0.1", 0)
        socket.addr[1]
      ensure
        socket&.close
      end
    end
  end
end
