require_relative "base"

module Support
  class TestServer
    module Routes
      # Core routes used by integration, hardening, fuzz, and unit specs.
      #
      # Handles: /health, /users, /posts, /echo, /delay, /error, /circuit
      class Core
        include Base

        def self.prefix = %r{^/(health|users|posts|echo|delay|error|circuit)}

        def initialize
          @circuit_failures = 0
        end

        def call(request)
          case request.path_info
          when "/health" then json(200, status: "ok")
          when %r{^/users} then handle_users(request)
          when %r{^/posts} then handle_posts(request)
          when %r{^/echo} then handle_echo(request)
          when %r{^/delay} then handle_delay(request)
          when %r{^/error} then handle_error(request)
          when %r{^/circuit} then handle_circuit(request)
          end
        end

        private

        def handle_users(request)
          case request.request_method
          when "GET"
            id = extract_id(request.path_info)
            json(200, id: id, name: "User #{id}", post_ids: [1, 2, 3].map { |n| (id * 10) + n })
          when "POST"
            body = parse_body(request)
            json(201, {id: rand(1000), **body})
          else
            json(405, error: "Method not allowed")
          end
        end

        def handle_posts(request)
          id = extract_id(request.path_info)
          json(200, id: id, title: "Post #{id}", body: "Content for post #{id}")
        end

        def handle_echo(request)
          body = request.body&.read || ""
          headers = request.env.select { |k, _| k.start_with?("HTTP_") }
            .transform_keys { |k|
              k.delete_prefix("HTTP_").tr("_", "-").split("-").map(&:capitalize).join("-")
            }
          json(200, method: request.request_method, headers: headers, body: begin
            JSON.parse(body)
          rescue
            nil
          end)
        end

        def handle_delay(request)
          seconds = request.path_info.split("/").last.to_f
          # Use Kernel.sleep to block the thread and trigger read timeouts
          # Async::Task.current.sleep doesn't block TCP which won't trigger timeouts
          Kernel.sleep(seconds)
          json(200, delayed: seconds)
        end

        def handle_error(request)
          status = [request.path_info.split("/").last.to_i, 500].find(&:positive?)
          json(status, error: "Error #{status}")
        end

        def handle_circuit(request)
          return json(200, reset: true).tap { @circuit_failures = 0 } if request.params["reset"]
          return json(500, failure: @circuit_failures += 1) if @circuit_failures < 3

          json(200, success: true, after_failures: @circuit_failures)
        end
      end
    end
  end
end
