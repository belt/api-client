require "spec_helper"
require "api_client"

RSpec.describe ApiClient::Base, :fuzz, :integration do \
  # rubocop:disable RSpec/SpecFilePathFormat,RSpec/MultipleDescribes
  let(:client) { client_for_server }

  describe "input fuzzing" do
    describe "path fuzzing" do
      it "handles random alphanumeric paths" do
        property_of { sized(50) { string(:alnum) } }.check(20) do |path|
          expect { client.get("/#{path}") }.not_to raise_error
        end
      end

      it "handles paths with special characters" do # rubocop:disable RSpec/ExampleLength
        paths = %w[
          /users/1
          /users/1/posts
          /path-with-dashes
          /path_with_underscores
          /path.with.dots
        ]

        paths.each do |path|
          expect { client.get(path) }.not_to raise_error
        end
      end

      it "handles empty path" do
        expect { client.get("") }.not_to raise_error
      end
    end

    describe "header fuzzing" do
      it "handles random header values" do # rubocop:disable RSpec/ExampleLength
        property_of {
          key = sized(20) { string(:alpha) }
          value = sized(50) { string(:print) }.gsub(/[\r\n]/, "")
          [key, value]
        }.check(20) do |key, value|
          expect { client.get("/echo", headers: {key => value}) }.not_to raise_error
        end
      end

      it "handles many headers" do
        headers = 20.times.each_with_object({}) do |i, h|
          h["X-Header-#{i}"] = "value-#{i}"
        end

        expect { client.get("/echo", headers: headers) }.not_to raise_error
      end
    end

    describe "body fuzzing" do
      it "handles random JSON bodies" do # rubocop:disable RSpec/ExampleLength
        property_of {
          dict(range(0, 5)) {
            [sized(10) { string(:alpha) }, choose(string, integer, boolean, nil)]
          }
        }.check(20) do |body|
          expect { client.post("/echo", body: body) }.not_to raise_error
        end
      end

      it "handles nil body" do
        expect { client.post("/echo", body: nil) }.not_to raise_error
      end

      it "handles empty hash body" do
        expect { client.post("/echo", body: {}) }.not_to raise_error
      end
    end

    describe "params fuzzing" do
      it "handles random query params" do # rubocop:disable RSpec/ExampleLength
        property_of {
          dict(range(0, 5)) {
            [sized(10) { string(:alpha) }, sized(20) { string(:alnum) }]
          }
        }.check(20) do |params|
          expect { client.get("/echo", params: params) }.not_to raise_error
        end
      end
    end
  end
end

RSpec.describe ApiClient::Configuration, :fuzz do # rubocop:disable RSpec/SpecFilePathFormat
  describe "timeout values" do
    it "handles various timeout values" do
      [0.1, 1, 5, 30, 60, 120].each do |timeout|
        config = build(:api_client_configuration, read_timeout: timeout)
        expect(config.read_timeout).to eq(timeout)
      end
    end

    it "handles float timeouts" do
      config = build(:api_client_configuration, read_timeout: 1.5)
      expect(config.read_timeout).to eq(1.5)
    end
  end

  describe "retry configuration" do
    it "handles various max values" do
      [0, 1, 2, 5, 10].each do |max|
        config = described_class.new
        config.retry.max = max
        expect(config.retry.max).to eq(max)
      end
    end

    it "handles various interval values" do
      [0.1, 0.5, 1.0, 2.0].each do |interval|
        config = described_class.new
        config.retry.interval = interval
        expect(config.retry.interval).to eq(interval)
      end
    end
  end

  describe "circuit configuration" do
    it "handles various threshold values" do
      [1, 2, 5, 10, 20].each do |threshold|
        config = described_class.new
        config.circuit.threshold = threshold
        expect(config.circuit.threshold).to eq(threshold)
      end
    end
  end
end
