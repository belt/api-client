require "spec_helper"
require "api_client"

# Parity tests compare Faraday and ApiClient responses side-by-side.
# rubocop:disable RSpec/ExampleLength, RSpec/MultipleExpectations
RSpec.describe "Faraday parity", :integration do # rubocop:disable RSpec/DescribeClass
  # Both clients point at the same test server so responses are comparable.
  let(:faraday) { Faraday.new(url: base_url) { |f| f.request :json } }
  let(:api) { client_for_server }

  # ------------------------------------------------------------------
  # Constructor contract
  # ------------------------------------------------------------------
  describe "constructor contract" do
    describe "url: keyword" do
      it "produces the same url_prefix for host-only URLs" do
        f = Faraday.new(url: "https://api.example.com")
        a = ApiClient.new(url: "https://api.example.com")

        expect(a.url_prefix.to_s).to eq(f.url_prefix.to_s)
      end

      it "preserves path from url: like Faraday does" do
        f = Faraday.new(url: "https://api.example.com/v1")
        a = ApiClient.new(url: "https://api.example.com/v1")

        expect(a.url_prefix.to_s).to eq(f.url_prefix.to_s)
      end

      it "preserves nested path from url:" do
        f = Faraday.new(url: "https://api.example.com/api/v2")
        a = ApiClient.new(url: "https://api.example.com/api/v2")

        expect(a.url_prefix.to_s).to eq(f.url_prefix.to_s)
      end

      it "preserves non-default port" do
        f = Faraday.new(url: "http://localhost:3000/api")
        a = ApiClient.new(url: "http://localhost:3000/api")

        expect(a.url_prefix.to_s).to eq(f.url_prefix.to_s)
      end

      it "explicit base_path overrides path from url:" do
        a = ApiClient.new(url: "https://api.example.com/v1", base_path: "/v2")

        expect(a.url_prefix.path).to eq("/v2")
      end

      it "url_prefix is a URI in both" do
        f = Faraday.new(url: "https://example.com")
        a = ApiClient.new(url: "https://example.com")

        expect(a.url_prefix).to be_a(f.url_prefix.class)
      end
    end

    describe "headers: keyword" do
      it "custom header is accessible the same way" do
        f = Faraday.new(url: base_url, headers: {"X-Parity" => "check"})
        a = ApiClient.new(url: base_url, headers: {"X-Parity" => "check"})

        expect(a.headers["X-Parity"]).to eq(f.headers["X-Parity"])
      end

      it "preserves custom header after override" do
        f = Faraday.new(url: base_url, headers: {"Accept" => "text/xml"})
        a = ApiClient.new(url: base_url, headers: {"Accept" => "text/xml"})

        expect(a.headers["Accept"]).to eq(f.headers["Accept"])
      end
    end

    describe "params: keyword" do
      it "stores params identically" do
        f = Faraday.new(url: base_url, params: {api_key: "abc"})
        a = ApiClient.new(url: base_url, params: {api_key: "abc"})

        expect(a.params[:api_key]).to eq(f.params[:api_key])
      end
    end

    describe "block configuration" do
      it "Faraday-style block sets adapter and timeouts" do
        f = Faraday.new(url: base_url) do |c|
          c.adapter :net_http
          c.options.open_timeout = 3
          c.options.read_timeout = 42
        end

        a = ApiClient.new(url: base_url) do |c|
          c.adapter :net_http
          c.options.open_timeout = 3
          c.options.read_timeout = 42
        end

        expect(a.options[:open_timeout]).to eq(f.options.open_timeout)
        expect(a.options[:read_timeout]).to eq(f.options.read_timeout)
      end
    end
  end

  # ------------------------------------------------------------------
  # Accessor contract — same names, same types
  # ------------------------------------------------------------------
  describe "accessor contract" do
    it "#url_prefix returns same type" do
      expect(api.url_prefix).to be_a(faraday.url_prefix.class)
    end

    it "#url_prefix resolves same host" do
      expect(api.url_prefix.host).to eq(faraday.url_prefix.host)
    end

    it "#url_prefix resolves same port" do
      expect(api.url_prefix.port).to eq(faraday.url_prefix.port)
    end

    it "#headers returns a Hash-like object" do
      expect(api.headers).to respond_to(:[])
      expect(faraday.headers).to respond_to(:[])
    end

    it "#params returns a Hash-like object" do
      expect(api.params).to respond_to(:[])
      expect(faraday.params).to respond_to(:[])
    end

    it "both respond to the same HTTP verbs" do
      %i[get post put patch delete head].each do |verb|
        expect(api).to respond_to(verb), "ApiClient missing ##{verb}"
        expect(faraday).to respond_to(verb), "Faraday missing ##{verb}"
      end
    end
  end

  # ------------------------------------------------------------------
  # Response contract — same class, same interface, same data
  # ------------------------------------------------------------------
  describe "response contract" do
    it "both return the exact same response class" do
      f_resp = faraday.get("/health")
      a_resp = api.get("/health")

      expect(a_resp.class).to eq(f_resp.class)
    end

    it ".status matches for 200" do
      f_resp = faraday.get("/health")
      a_resp = api.get("/health")

      expect(a_resp.status).to eq(f_resp.status)
    end

    it ".status type matches" do
      f_resp = faraday.get("/health")
      a_resp = api.get("/health")

      expect(a_resp.status).to be_a(f_resp.status.class)
    end

    it ".body type matches" do
      f_resp = faraday.get("/health")
      a_resp = api.get("/health")

      expect(a_resp.body).to be_a(f_resp.body.class)
    end

    it ".body content matches for same endpoint" do
      f_resp = faraday.get("/health")
      a_resp = api.get("/health")

      expect(JSON.parse(a_resp.body)).to eq(JSON.parse(f_resp.body))
    end

    it ".headers type matches" do
      f_resp = faraday.get("/health")
      a_resp = api.get("/health")

      expect(a_resp.headers).to be_a(f_resp.headers.class)
    end

    it ".headers content-type matches" do
      f_resp = faraday.get("/health")
      a_resp = api.get("/health")

      expect(a_resp.headers["content-type"]).to eq(f_resp.headers["content-type"])
    end

    it "#success? matches for 200" do
      f_resp = faraday.get("/health")
      a_resp = api.get("/health")

      expect(a_resp.success?).to eq(f_resp.success?)
    end

    it "#success? matches for 404" do
      f_resp = faraday.get("/error/404")
      a_resp = client_for_server(retry: {max: 0}).get("/error/404")

      expect(a_resp.success?).to eq(f_resp.success?)
    end

    it "#success? matches for 500" do
      f_resp = faraday.get("/error/500")
      a_resp = client_for_server(retry: {max: 0}).get("/error/500")

      expect(a_resp.success?).to eq(f_resp.success?)
    end

    describe "response interface" do
      it "exposes the same public methods" do
        f_resp = faraday.get("/health")
        a_resp = api.get("/health")

        # Core Faraday::Response interface that downstream code relies on
        %i[status body headers success? reason_phrase].each do |method|
          expect(a_resp).to respond_to(method),
            "ApiClient response missing ##{method} (Faraday has it)"
          expect(f_resp).to respond_to(method),
            "Faraday response missing ##{method} (contract changed?)"
        end
      end
    end
  end

  # ------------------------------------------------------------------
  # HTTP verb contract — same call, same result
  # ------------------------------------------------------------------
  describe "HTTP verb contract" do
    describe "GET" do
      it "simple GET returns same status and body" do
        f_resp = faraday.get("/users/1")
        a_resp = api.get("/users/1")

        expect(a_resp.status).to eq(f_resp.status)
        expect(JSON.parse(a_resp.body)).to eq(JSON.parse(f_resp.body))
      end

      it "GET with positional params returns same status" do
        f_resp = faraday.get("/echo", {page: 1})
        a_resp = api.get("/echo", {page: 1})

        expect(a_resp.status).to eq(f_resp.status)
      end

      it "GET with block returns same status" do
        f_resp = faraday.get("/echo") { |req| req.params["page"] = 2 }
        a_resp = api.get("/echo") { |req| req.params["page"] = 2 }

        expect(a_resp.status).to eq(f_resp.status)
      end
    end

    describe "POST" do
      it "POST with body returns same status" do
        f_resp = faraday.post("/users", {name: "parity"}.to_json)
        a_resp = api.post("/users", body: {name: "parity"})

        expect(a_resp.status).to eq(f_resp.status)
      end
    end

    describe "PUT" do
      it "PUT returns same status" do
        f_resp = faraday.put("/echo")
        a_resp = api.put("/echo")

        expect(a_resp.status).to eq(f_resp.status)
      end
    end

    describe "PATCH" do
      it "PATCH returns same status" do
        f_resp = faraday.patch("/echo")
        a_resp = api.patch("/echo")

        expect(a_resp.status).to eq(f_resp.status)
      end
    end

    describe "DELETE" do
      it "DELETE returns same status" do
        f_resp = faraday.delete("/echo")
        a_resp = api.delete("/echo")

        expect(a_resp.status).to eq(f_resp.status)
      end
    end

    describe "HEAD" do
      it "HEAD returns same status" do
        f_resp = faraday.head("/health")
        a_resp = api.head("/health")

        expect(a_resp.status).to eq(f_resp.status)
      end
    end
  end

  # ------------------------------------------------------------------
  # Error contract — same exceptions for same failures
  # ------------------------------------------------------------------
  describe "error contract" do
    it "both raise Faraday::ConnectionFailed on unreachable host" do
      f = Faraday.new(url: "http://localhost:1")
      a = ApiClient::Base.new(url: "http://localhost:1")

      faraday_error = begin
        f.get("/")
      rescue => e
        e.class
      end

      api_error = begin
        a.get("/")
      rescue => e
        e.class
      end

      expect(api_error).to eq(faraday_error)
    end

    it "both return 4xx without raising by default" do
      f_resp = faraday.get("/error/404")
      a_resp = client_for_server(retry: {max: 0}).get("/error/404")

      expect(a_resp.status).to eq(f_resp.status)
      expect(a_resp.class).to eq(f_resp.class)
    end

    it "both return 5xx without raising by default" do
      f_resp = faraday.get("/error/500")
      a_resp = client_for_server(retry: {max: 0}).get("/error/500")

      expect(a_resp.status).to eq(f_resp.status)
      expect(a_resp.class).to eq(f_resp.class)
    end
  end

  # ------------------------------------------------------------------
  # FaradayBuilder probe (unit tests — no Faraday comparison needed)
  # ------------------------------------------------------------------
  describe "FaradayBuilder probe" do
    describe "#faraday_style?" do
      it "false for fresh builder" do
        expect(ApiClient::FaradayBuilder.new.faraday_style?).to be false
      end

      it "true after f.request" do
        b = ApiClient::FaradayBuilder.new
        b.request(:json)
        expect(b.faraday_style?).to be true
      end

      it "true after f.response" do
        b = ApiClient::FaradayBuilder.new
        b.response(:json)
        expect(b.faraday_style?).to be true
      end

      it "true after f.adapter" do
        b = ApiClient::FaradayBuilder.new
        b.adapter(:net_http)
        expect(b.faraday_style?).to be true
      end

      it "true after f.options" do
        b = ApiClient::FaradayBuilder.new
        b.options
        expect(b.faraday_style?).to be true
      end

      it "false for Configuration-style setter calls" do
        b = ApiClient::FaradayBuilder.new
        b.read_timeout = 30
        expect(b.faraday_style?).to be false
      end
    end

    describe "#apply_to" do
      let(:config) { ApiClient::Configuration.new }

      it "applies adapter" do
        b = ApiClient::FaradayBuilder.new
        b.adapter(:net_http)
        b.apply_to(config)
        expect(config.adapter).to eq(:net_http)
      end

      it "applies timeouts" do
        b = ApiClient::FaradayBuilder.new
        b.options.open_timeout = 3
        b.options.read_timeout = 42
        b.options.write_timeout = 7
        b.apply_to(config)

        expect(config.open_timeout).to eq(3)
        expect(config.read_timeout).to eq(42)
        expect(config.write_timeout).to eq(7)
      end

      it "maps timeout to read_timeout" do
        b = ApiClient::FaradayBuilder.new
        b.options.timeout = 15
        b.apply_to(config)
        expect(config.read_timeout).to eq(15)
      end

      it "enables logging from response :logger" do
        b = ApiClient::FaradayBuilder.new
        b.response(:logger)
        b.apply_to(config)
        expect(config.log_requests).to be true
      end

      it "captures custom logger and bodies" do
        logger = Logger.new(IO::NULL)
        b = ApiClient::FaradayBuilder.new
        b.response(:logger, logger, bodies: true)
        b.apply_to(config)

        expect(config.logger).to eq(logger)
        expect(config.log_bodies).to be true
      end

      it "merges headers with defaults" do
        b = ApiClient::FaradayBuilder.new
        b.headers["X-New"] = "yes"
        b.apply_to(config)

        expect(config.default_headers).to include("X-New" => "yes", "Accept" => "application/json")
      end

      it "merges params with defaults" do
        b = ApiClient::FaradayBuilder.new
        b.params["v"] = "2"
        b.apply_to(config)
        expect(config.default_params).to include("v" => "2")
      end

      it "preserves adapter when none set" do
        original = config.adapter
        b = ApiClient::FaradayBuilder.new
        b.request(:json)
        b.apply_to(config)
        expect(config.adapter).to eq(original)
      end
    end

    describe "OptionsProxy" do
      it "stores all timeout types" do
        p = ApiClient::FaradayBuilder::OptionsProxy.new
        p.timeout = 10
        p.open_timeout = 3
        p.read_timeout = 20
        p.write_timeout = 5

        expect([p.timeout, p.open_timeout, p.read_timeout, p.write_timeout])
          .to eq([10, 3, 20, 5])
      end

      it "defaults to nil" do
        p = ApiClient::FaradayBuilder::OptionsProxy.new
        expect([p.timeout, p.open_timeout, p.read_timeout, p.write_timeout])
          .to eq([nil, nil, nil, nil])
      end
    end
  end
end
# rubocop:enable RSpec/ExampleLength, RSpec/MultipleExpectations
