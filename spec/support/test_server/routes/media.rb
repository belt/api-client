require_relative "base"

module Support
  class TestServer
    module Routes
      # MediaTranscoder: /media/assets/:id/variants → variant_ids,
      #   /transcode/:id → transcoded output
      class Media
        include Base

        def self.prefix = %r{^/(media|transcode)}

        def call(request)
          case request.path_info
          when %r{^/media/assets/([^/]+)/variants$}
            json(200, variant_ids: %w[720p 1080p])
          when %r{^/transcode/([^/]+)$}
            json(200, output_url: "https://cdn.test/out.mp4")
          end
        end
      end
    end
  end
end
