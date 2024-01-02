require "spec_helper"
require "api_client"

RSpec.describe ApiClient::HttpVerbs do
  let(:test_class) do
    Class.new do
      extend ApiClient::HttpVerbs

      attr_accessor :last_call

      def request(verb, path, params:, headers:, body: nil)
        @last_call = {verb: verb, path: path, params: params, headers: headers, body: body}
        "response"
      end

      def connection
        self
      end

      def with_wrapper
        yield
      end

      define_bodyless_verbs(target: :request)
      define_body_verbs(target: :request)
    end
  end

  let(:instance) { test_class.new }

  describe "::BODYLESS_VERBS" do
    it "includes get, head, delete, trace" do
      expect(ApiClient::HttpVerbs::BODYLESS_VERBS).to eq(%i[get head delete trace])
    end
  end

  describe "::BODY_VERBS" do
    it "includes post, put, patch" do
      expect(ApiClient::HttpVerbs::BODY_VERBS).to eq(%i[post put patch])
    end
  end

  describe "::HTTP_VERBS" do
    it "combines all verbs" do
      expect(ApiClient::HttpVerbs::HTTP_VERBS).to eq(%i[get head delete trace post put patch])
    end
  end

  describe "::EMPTY_HASH" do
    it "is frozen" do
      expect(ApiClient::HttpVerbs::EMPTY_HASH).to be_frozen
    end
  end

  describe ".define_bodyless_verbs" do
    it "defines get method" do
      result = instance.get("/path")
      expect(instance.last_call).to include(verb: :get, path: "/path")
      expect(result).to eq("response")
    end

    it "defines head method" do
      instance.head("/path")
      expect(instance.last_call[:verb]).to eq(:head)
    end

    it "defines delete method" do
      instance.delete("/path")
      expect(instance.last_call[:verb]).to eq(:delete)
    end

    it "defines trace method" do
      instance.trace("/path")
      expect(instance.last_call[:verb]).to eq(:trace)
    end

    it "passes params and headers" do
      instance.get("/path", params: {q: "test"}, headers: {"X-Custom" => "value"})
      expect(instance.last_call[:params]).to eq({q: "test"})
      expect(instance.last_call[:headers]).to eq({"X-Custom" => "value"})
    end

    it "uses empty hash defaults" do
      instance.get("/path")
      expect(instance.last_call[:params]).to eq({})
      expect(instance.last_call[:headers]).to eq({})
    end
  end

  describe ".define_body_verbs" do
    it "defines post method" do
      instance.post("/path")
      expect(instance.last_call[:verb]).to eq(:post)
    end

    it "defines put method" do
      instance.put("/path")
      expect(instance.last_call[:verb]).to eq(:put)
    end

    it "defines patch method" do
      instance.patch("/path")
      expect(instance.last_call[:verb]).to eq(:patch)
    end

    it "passes body" do
      instance.post("/path", body: {data: "value"})
      expect(instance.last_call[:body]).to eq({data: "value"})
    end

    it "passes params and headers" do
      instance.post("/path", params: {q: "test"}, headers: {"X-Custom" => "value"})
      expect(instance.last_call[:params]).to eq({q: "test"})
      expect(instance.last_call[:headers]).to eq({"X-Custom" => "value"})
    end
  end

  describe ".define_http_verbs" do
    let(:combined_class) do
      Class.new do
        extend ApiClient::HttpVerbs

        attr_accessor :last_call

        def request(verb, path, params:, headers:, body: nil)
          @last_call = {verb: verb, path: path}
        end

        define_http_verbs(target: :request)
      end
    end

    it "defines all HTTP verbs" do
      instance = combined_class.new
      ApiClient::HttpVerbs::HTTP_VERBS.each do |verb|
        expect(instance).to respond_to(verb)
      end
    end
  end

  describe "wrapper option" do
    let(:inner_connection) do
      Class.new do
        attr_accessor :last_verb

        ApiClient::HttpVerbs::BODYLESS_VERBS.each do |verb|
          define_method(verb) do |path, **opts|
            @last_verb = verb
            "inner-#{verb}"
          end
        end

        ApiClient::HttpVerbs::BODY_VERBS.each do |verb|
          define_method(verb) do |path, **opts|
            @last_verb = verb
            "inner-#{verb}"
          end
        end
      end.new
    end

    let(:wrapped_class) do
      conn = inner_connection
      Class.new do
        extend ApiClient::HttpVerbs

        attr_accessor :wrapper_called

        define_method(:connection) { conn }

        def with_wrapper
          @wrapper_called = true
          yield
        end

        define_bodyless_verbs(target: :connection, wrapper: :with_wrapper)
        define_body_verbs(target: :connection, wrapper: :with_wrapper)
      end
    end

    it "wraps bodyless verb calls via wrapper: parameter" do
      instance = wrapped_class.new
      instance.get("/path")
      expect(instance.wrapper_called).to be true
    end

    it "wraps body verb calls via wrapper: parameter" do
      instance = wrapped_class.new
      instance.post("/path")
      expect(instance.wrapper_called).to be true
    end

    it "delegates bodyless verbs through connection target" do
      instance = wrapped_class.new
      instance.head("/path")
      expect(inner_connection.last_verb).to eq(:head)
    end

    it "delegates body verbs through connection target" do
      instance = wrapped_class.new
      instance.put("/path")
      expect(inner_connection.last_verb).to eq(:put)
    end
  end
end
