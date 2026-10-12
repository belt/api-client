# frozen_string_literal: true

module Support
  module ServerCompat
    class HealthApp
      BODY = '{"status":"ok"}'

      def call(env)
        return [404, {"content-type" => "text/plain"}, ["not found"]] unless env["PATH_INFO"] == "/health"

        [200, {"content-type" => "application/json", "content-length" => BODY.bytesize.to_s}, [BODY]]
      end
    end
  end
end
