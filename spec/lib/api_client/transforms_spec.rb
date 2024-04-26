require "spec_helper"
require "api_client"

RSpec.describe ApiClient::Transforms do
  describe "::REGISTRY" do
    it "includes :identity, :json, :sha256" do
      expect(described_class::REGISTRY.keys).to contain_exactly(:identity, :json, :sha256)
    end

    it "is frozen" do
      expect(described_class::REGISTRY).to be_frozen
    end
  end

  describe ".apply" do
    it "applies :identity transform" do
      expect(described_class.apply(:identity, "hello")).to eq("hello")
    end

    it "applies :json transform" do
      expect(described_class.apply(:json, '{"a":1}')).to eq({"a" => 1})
    end

    it "applies :sha256 transform" do
      result = described_class.apply(:sha256, "hello")
      expect(result).to eq(Digest::SHA256.hexdigest("hello"))
    end

    it "raises ArgumentError for unknown transform" do
      expect { described_class.apply(:unknown, "data") }
        .to raise_error(ArgumentError, /Unknown transform/)
    end
  end

  describe ".valid?" do
    it "returns true for :json" do
      expect(described_class.valid?(:json)).to be true
    end

    it "returns true for :identity" do
      expect(described_class.valid?(:identity)).to be true
    end

    it "returns true for :sha256" do
      expect(described_class.valid?(:sha256)).to be true
    end

    it "returns false for unknown transforms" do
      expect(described_class.valid?(:unknown)).to be false
    end
  end

  describe ".available" do
    it "returns array of transform names" do
      expect(described_class.available).to contain_exactly(:identity, :json, :sha256)
    end
  end

  describe ApiClient::Transforms::Recipe do
    describe ".default" do
      subject(:recipe) { described_class.default }

      it "extracts body" do
        expect(recipe.extract).to eq(:body)
      end

      it "transforms as json" do
        expect(recipe.transform).to eq(:json)
      end
    end

    describe ".identity" do
      subject(:recipe) { described_class.identity }

      it "extracts body" do
        expect(recipe.extract).to eq(:body)
      end

      it "applies identity transformation" do
        expect(recipe.transform).to eq(:identity)
      end
    end

    describe ".headers" do
      subject(:recipe) { described_class.headers }

      it "extracts headers" do
        expect(recipe.extract).to eq(:headers)
      end

      it "applies identity transformation" do
        expect(recipe.transform).to eq(:identity)
      end
    end

    describe ".status" do
      subject(:recipe) { described_class.status }

      it "extracts status" do
        expect(recipe.extract).to eq(:status)
      end

      it "applies identity transformation" do
        expect(recipe.transform).to eq(:identity)
      end
    end

    describe "#new" do
      it "creates recipe with custom extract" do
        recipe = described_class.new(extract: :headers, transform: :sha256)
        expect(recipe.extract).to eq(:headers)
      end

      it "creates recipe with custom transform" do
        recipe = described_class.new(extract: :headers, transform: :sha256)
        expect(recipe.transform).to eq(:sha256)
      end
    end
  end
end
