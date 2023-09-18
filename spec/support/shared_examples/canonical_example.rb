require "faraday"

# Shared examples for canonical RequestFlow examples
#
# Every example in lib/api_client/examples follows the same five-step pipeline:
#   fetch → then → fan_out → *_map/process → collect
#
# This shared example exercises the full pipeline with stubbed HTTP,
# covering: happy path, empty input, constant introspection, and
# request flow construction.
#
# Required `let` bindings in the including context:
#   - example_class: The example class under test
#   - invoke_method: Proc that calls the example's public method
#   - initial_response_body: JSON string for the initial fetch response
#   - id_key: String key in the parsed initial response containing IDs
#   - fan_out_response_body: JSON string for each fan-out response
#
RSpec.shared_examples "canonical request flow example" do
  subject(:client) { example_class.new(service_uri: "http://example.test") }

  let(:ids) { JSON.parse(initial_response_body)[id_key] }

  before do
    # Stub all requests to example.test — the initial fetch returns the
    # ID list, and all subsequent fan-out requests return the fan-out body.
    # WebMock processes stubs in reverse registration order, so the
    # catch-all fan-out stub goes first, then the initial fetch overrides
    # for matching paths.
    stub_request(:any, /example\.test/)
      .to_return(
        status: 200, body: fan_out_response_body, headers: {"content-type" => "application/json"}
      )
  end

  describe "class constants" do
    it "exposes ADAPTER constant" do
      expect(example_class::ADAPTER).to be_a(Symbol)
    end

    it "exposes PROCESSOR constant" do
      expect(example_class::PROCESSOR).to be_a(Symbol)
    end

    it "ADAPTER is a known adapter" do
      expect(example_class::ADAPTER).to be_in(%i[typhoeus async ractor concurrent sequential])
    end

    it "PROCESSOR is a known processor" do
      expect(example_class::PROCESSOR).to be_in(%i[ractor async concurrent sequential])
    end
  end

  describe "inheritance" do
    it "inherits from ApiClient::Base" do
      expect(example_class).to be < ApiClient::Base
    end
  end

  describe "#initialize" do
    it "creates an instance" do
      expect(client).to be_a(example_class)
    end

    it "accepts keyword overrides" do
      custom = example_class.new(service_uri: "http://custom.test", read_timeout: 99)
      stub_request(:any, /custom\.test/)
        .to_return(
          status: 200, body: fan_out_response_body, headers: {"content-type" => "application/json"}
        )
      expect(custom.config.read_timeout).to eq(99)
    end

    it "sets base_path via config" do
      expect(client.config.base_path).not_to eq("/")
    end
  end

  describe "request flow execution" do
    before do
      # Override the initial fetch to return the ID list.
      # First request in the flow is the initial fetch; subsequent are fan-out.
      WebMock.reset!
      call_count = Concurrent::AtomicFixnum.new(0)
      initial_body = initial_response_body
      fanout_body = fan_out_response_body
      stub_request(:any, /example\.test/).to_return do |_request|
        body = (call_count.increment == 1) ? initial_body : fanout_body
        {status: 200, body: body, headers: {"content-type" => "application/json"}}
      end
    end

    it "returns an array of results" do
      results = invoke_method.call(client)
      expect(results).to be_an(Array)
    end

    it "returns results matching fan-out count" do
      results = invoke_method.call(client)
      expect(results.size).to eq(ids.size)
    end
  end

  describe "#request_flow" do
    it "returns a RequestFlow" do
      expect(client.request_flow).to be_a(ApiClient::RequestFlow)
    end
  end

  context "when initial fetch returns empty IDs" do
    before do
      WebMock.reset!
      empty_body = JSON.generate({id_key => []})
      stub_request(:any, /example\.test/)
        .to_return(status: 200, body: empty_body, headers: {"content-type" => "application/json"})
    end

    it "returns empty array" do
      results = invoke_method.call(client)
      expect(results).to eq([])
    end
  end
end
