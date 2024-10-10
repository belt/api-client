module Middlewares
  module Faraday
    # add X-Request-Faraday-Start in milliseconds to track queue times
    class OpenTelemetryHeaders < ::Faraday::Middleware
      HEADER_NAME = "X-Request-Faraday-Start".freeze

      def call(env)
        env[:request_headers][HEADER_NAME] =
          (Process.clock_gettime(Process::CLOCK_REALTIME) * 1000).to_i.to_s
        @app.call(env)
      end
    end
  end
end
