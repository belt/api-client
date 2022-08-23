# frozen_string_literal: true

module Middlewares
  module Faraday
    # add X-Request-Faraday-Start in milliseconds to track queue times
    class NewRelicTrackingHeaders < ::Faraday::Middleware
      HEADER_NAME = 'X-Request-Faraday-Start'

      def call(env)
        env[:request_headers][HEADER_NAME] = (Time.now.to_f * 1000).to_i.to_s
        @app.call env
      end
    end
  end
end
