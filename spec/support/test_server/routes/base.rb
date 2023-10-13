module Support
  class TestServer
    module Routes
      # Base route module — provides JSON response helper and route registration DSL.
      #
      # Every route module includes this and defines a `call(request)` method
      # that returns `nil` (no match) or a Rack-style `[status, headers, body]` triple.
      module Base
        JSON_CONTENT_TYPE = {"content-type" => "application/json"}.freeze

        def self.included(base)
          base.extend(ClassMethods)
        end

        module ClassMethods
          # Rack-style prefix this route module handles.
          # @return [String, Regexp]
          def prefix
            raise NotImplementedError, "#{name} must define .prefix"
          end
        end

        private

        def json(status, body)
          [status, JSON_CONTENT_TYPE, [body.to_json]]
        end

        def extract_id(path)
          [path.split("/").last.to_i, 1].max
        end

        def parse_body(request)
          JSON.parse(request.body&.read || "{}")
        rescue JSON::ParserError
          {}
        end
      end
    end
  end
end
