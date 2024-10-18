require "spec_helper"
require ApiClient.root.join("lib/middlewares/faraday/open_telemetry_headers").to_s

RSpec.describe Middlewares::Faraday::OpenTelemetryHeaders do
  subject(:middleware) { described_class.new(app) }

  let(:app) { instance_double(Faraday::Middleware) }
  let(:env) { {request_headers: {}} }

  describe "::HEADER_NAME" do
    it "is X-Request-Faraday-Start" do
      expect(described_class::HEADER_NAME).to eq("X-Request-Faraday-Start")
    end
  end

  describe "#call" do
    before do
      allow(app).to receive(:call).with(env).and_return(env)
    end

    it "adds tracking header" do
      middleware.call(env)
      expect(env[:request_headers]).to have_key("X-Request-Faraday-Start")
    end

    it "sets header to milliseconds timestamp" do
      now = Process.clock_gettime(Process::CLOCK_REALTIME)
      allow(Process).to receive(:clock_gettime).and_call_original
      allow(Process).to receive(:clock_gettime).with(Process::CLOCK_REALTIME).and_return(now)
      middleware.call(env)
      expect(env[:request_headers]["X-Request-Faraday-Start"].to_i).to eq((now * 1000).to_i)
    end

    it "calls next middleware" do
      middleware.call(env)
      expect(app).to have_received(:call).with(env)
    end

    it "returns app result" do
      result = middleware.call(env)
      expect(result).to eq(env)
    end
  end

  describe "integration with Faraday" do
    it "can be used as Faraday middleware" do # rubocop:disable RSpec/ExampleLength
      conn = Faraday.new do |f|
        f.use described_class
        f.adapter :test do |stub|
          stub.get("/test") { [200, {}, "ok"] }
        end
      end

      response = conn.get("/test")
      expect(response.status).to eq(200)
    end
  end

  describe "header propagation across execution paths", :integration do
    let(:header_name) { described_class::HEADER_NAME }

    # Build a Faraday connection with the middleware wired in, pointing at
    # the real test server so we can inspect echoed headers.
    def faraday_with_middleware(url:, adapter: :net_http)
      Faraday.new(url: url) do |f|
        f.use described_class
        f.request :json
        f.adapter adapter
      end
    end

    def echoed_header(response)
      body = JSON.parse(response.body)
      # Rack normalises header names: X-Request-Faraday-Start → X-Request-Faraday-Start
      body["headers"]&.find { |k, _| k.casecmp(header_name).zero? }&.last
    end

    describe "sequential (Connection)" do
      it "delivers the header to the server" do # rubocop:disable RSpec/ExampleLength,RSpec/MultipleExpectations
        conn = faraday_with_middleware(url: base_url)
        response = conn.get("/echo")

        expect(response.status).to eq(200)
        value = echoed_header(response)
        expect(value).not_to be_nil
        expect(value.to_i).to be > 0
      end

      it "sets a unique timestamp per request" do # rubocop:disable RSpec/ExampleLength,RSpec/MultipleExpectations
        conn = faraday_with_middleware(url: base_url)

        ts1 = echoed_header(conn.get("/echo"))
        sleep 0.01
        ts2 = echoed_header(conn.get("/echo"))

        expect(ts1.to_i).to be > 0
        expect(ts2.to_i).to be >= ts1.to_i
      end
    end

    describe "batch via ConcurrentAdapter",
      if: ApiClient::Backend.available?(:concurrent) do
      before { ApiClient::Backend.resolve(:concurrent) }

      it "delivers the header on every request in the batch" do # rubocop:disable RSpec/ExampleLength,RSpec/MultipleExpectations
        # ConcurrentAdapter builds its own Faraday connections internally,
        # so we verify by building an equivalent connection with the
        # middleware and running concurrent requests through it.
        conn = faraday_with_middleware(url: base_url)

        responses = 3.times.map do
          Thread.new { conn.get("/echo") } # rubocop:disable ThreadSafety/NewThread
        end.map(&:value)

        responses.each do |response|
          expect(response.status).to eq(200)
          value = echoed_header(response)
          expect(value).not_to be_nil, "Expected #{header_name} header in echoed response"
          expect(value.to_i).to be > 0
        end
      end
    end

    describe "Typhoeus adapter (bypasses Faraday middleware)",
      if: ApiClient::Backend.available?(:typhoeus) do
      before { ApiClient::Backend.resolve(:typhoeus) }

      it "does NOT inject the header (Typhoeus uses libcurl, not Faraday middleware)" do # rubocop:disable RSpec/ExampleLength
        config = build(:api_client_configuration, service_uri: base_url)
        adapter = ApiClient::Adapters::TyphoeusAdapter.new(config)

        responses = adapter.execute([{method: :get, path: "/echo"}])
        body = JSON.parse(responses.first.body)
        header_value = body["headers"]&.find { |k, _| k.casecmp(header_name).zero? }&.last

        expect(header_value).to be_nil,
          "Typhoeus bypasses Faraday middleware — header should not be present. " \
          "If this fails, Typhoeus gained Faraday middleware support and this spec should be updated."
      end
    end

    describe "Async adapter (bypasses Faraday middleware)",
      if: ApiClient::Backend.available?(:async) do
      before { ApiClient::Backend.resolve(:async) }

      it "does NOT inject the header (Async uses async-http, not Faraday middleware)" do # rubocop:disable RSpec/ExampleLength
        config = build(:api_client_configuration, service_uri: base_url)
        adapter = ApiClient::Adapters::AsyncAdapter.new(config)

        responses = adapter.execute([{method: :get, path: "/echo"}])
        body = JSON.parse(responses.first.body)
        header_value = body["headers"]&.find { |k, _| k.casecmp(header_name).zero? }&.last

        expect(header_value).to be_nil,
          "Async bypasses Faraday middleware — header should not be present. " \
          "If this fails, the Async adapter gained Faraday middleware support and this spec should be updated."
      end
    end
  end
end
