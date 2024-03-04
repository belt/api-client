require "api_client"
require "api_client/processing/registry"
require "api_client/jwt"

# Verifies that all optional gems use top-level begin/rescue LoadError
# and that availability checks return proper booleans (not strings).
#
# The gems under test: jwt, concurrent-ruby, async/async-http,
# async-container, typhoeus, stoplight, faraday-typhoeus.
#
# Fan-out (async/async-barrier) is intentionally excluded — async
# is a hard dependency there.
RSpec.describe ApiClient do # rubocop:disable RSpec/DescribeClass,RSpec/SpecFilePathFormat
  describe "backend availability returns booleans" do
    %i[typhoeus async concurrent sequential].each do |backend|
      it ":#{backend} returns true or false" do
        result = ApiClient::Backend::Registry.available?(backend)
        expect(result).to be(true).or be(false)
      end
    end
  end

  describe "processor availability returns booleans" do
    %i[ractor async concurrent sequential].each do |processor|
      it ":#{processor} returns true or false" do
        result = ApiClient::Processing::Registry.available?(processor)
        expect(result).to be(true).or be(false)
      end
    end
  end

  describe "JWT auditor availability" do
    it "returns true or false" do
      result = ApiClient::Jwt::Auditor.available?
      expect(result).to be(true).or be(false)
    end
  end

  describe "top-level guarded requires" do
    guarded_files = {
      "lib/api_client/jwt/auditor.rb" => "jwt",
      "lib/api_client/processing/async_processor.rb" => "async/container",
      "lib/api_client/processing/concurrent_processor.rb" => "concurrent",
      "lib/api_client/adapters/async_adapter.rb" => "async",
      "lib/api_client/adapters/concurrent_adapter.rb" => "concurrent",
      "lib/api_client/adapters/typhoeus_adapter.rb" => "typhoeus",
      "lib/api_client/circuit.rb" => "stoplight",
      "lib/api_client/connection.rb" => "faraday/typhoeus"
    }.freeze

    guarded_files.each do |file, gem_name|
      describe file do
        let(:source) { File.read(described_class.root.join(file)) }

        it "guards require '#{gem_name}' with begin/rescue LoadError" do
          expect(source).to match(
            /^begin\s*\n(?:\s+require\s+["'][^"']+["']\s*\n)*\s*require\s+["']#{Regexp.escape(gem_name)}["']/
          )
        end

        it "has rescue LoadError" do
          expect(source).to match(/^rescue\s+LoadError/)
        end

        it "does not have inline require with rescue LoadError" do
          source.lines.each_with_index do |line, idx|
            next unless line.match?(/^\s{6,}require\s+["']#{Regexp.escape(gem_name)}["']/)
            next_meaningful = source.lines[(idx + 1)..].find { |l| !l.strip.empty? }
            expect(next_meaningful).not_to match(/rescue\s+LoadError/)
          end
        end
      end
    end
  end

  describe "graceful fallback when gems unavailable" do
    it "backend registry falls back to :sequential" do
      expect(ApiClient::Backend::Registry.available?(:sequential)).to be true
    end

    it "processor registry falls back to :sequential" do
      expect(ApiClient::Processing::Registry.available?(:sequential)).to be true
    end

    it "backend detect returns a symbol" do
      expect(ApiClient::Backend::Registry.detect).to be_a(Symbol)
    end

    it "backend detect returns a core backend" do
      result = ApiClient::Backend::Registry.detect
      expect(ApiClient::Backend::Registry::CORE_BACKENDS).to include(result)
    end

    it "processor detect returns a symbol" do
      expect(ApiClient::Processing::Registry.detect).to be_a(Symbol)
    end

    it "processor detect returns a known processor" do
      result = ApiClient::Processing::Registry.detect
      expect(ApiClient::Processing::Registry::PROCESSORS).to include(result)
    end
  end
end
