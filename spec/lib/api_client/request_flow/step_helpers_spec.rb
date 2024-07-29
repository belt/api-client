require "spec_helper"
require "api_client"

RSpec.describe ApiClient::RequestFlow::StepHelpers do
  describe ".build_processor_step_options" do
    it "builds options hash with all parameters" do
      block = proc { |x| x }
      recipe = ApiClient::Transforms::Recipe.default
      errors = ApiClient::Processing::ErrorStrategy.skip
      opts = described_class.build_processor_step_options(
        recipe: recipe,
        errors: errors,
        block: block
      )

      expect(opts).to eq(
        recipe: recipe,
        errors: errors,
        block: block
      )
    end

    it "handles nil values" do
      opts = described_class.build_processor_step_options(
        recipe: ApiClient::Transforms::Recipe.default,
        errors: nil,
        block: nil
      )

      expect(opts[:errors]).to be_nil
      expect(opts[:block]).to be_nil
    end
  end

  describe ".execute_processor" do
    let(:mock_processor) { instance_double("Processor") }
    let(:mock_processor_class) { class_double("ProcessorClass", new: mock_processor) }
    let(:registry) { double("Registry") }
    let(:items) { [double(body: '{"id":1}'), double(body: '{"id":2}')] }

    it "resolves processor from registry and calls map" do
      allow(registry).to receive(:processor).with(:parallel_map).and_return(mock_processor_class)
      allow(mock_processor).to receive(:map).and_return([{"id" => 1}, {"id" => 2}])

      recipe = ApiClient::Transforms::Recipe.default
      opts = {recipe: recipe, errors: nil, block: nil}
      result = described_class.execute_processor(:parallel_map, opts, items, registry)

      expect(result).to eq([{"id" => 1}, {"id" => 2}])
      expect(mock_processor).to have_received(:map).with(
        items,
        recipe: recipe,
        errors: nil,
        &nil
      )
    end

    it "passes block to processor map" do
      block = proc { |x| x["id"] * 2 }
      allow(registry).to receive(:processor).with(:async_map).and_return(mock_processor_class)
      allow(mock_processor).to receive(:map).and_return([2, 4])

      recipe = ApiClient::Transforms::Recipe.default
      errors = ApiClient::Processing::ErrorStrategy.skip
      opts = {recipe: recipe, errors: errors, block: block}
      result = described_class.execute_processor(:async_map, opts, items, registry)

      expect(result).to eq([2, 4])
    end

    it "wraps items in Array" do
      allow(registry).to receive(:processor).with(:concurrent_map).and_return(mock_processor_class)
      allow(mock_processor).to receive(:map).and_return(["result"])

      recipe = ApiClient::Transforms::Recipe.new(extract: :identity, transform: :identity)
      opts = {recipe: recipe, errors: nil, block: nil}
      described_class.execute_processor(:concurrent_map, opts, ["single"], registry)

      expect(mock_processor).to have_received(:map).with(
        ["single"],
        recipe: recipe,
        errors: nil,
        &nil
      )
    end
  end

  describe ".execute_with_processor" do
    let(:mock_processor) { instance_double("Processor") }
    let(:mock_processor_class) { class_double("ProcessorClass", new: mock_processor) }

    it "instantiates processor and calls map" do
      allow(mock_processor).to receive(:map).and_return([{"id" => 1}])

      recipe = ApiClient::Transforms::Recipe.default
      opts = {recipe: recipe, errors: nil, block: nil}
      result = described_class.execute_with_processor(mock_processor_class, opts, [double])

      expect(result).to eq([{"id" => 1}])
      expect(mock_processor_class).to have_received(:new)
    end

    it "passes block from opts" do
      block = proc { |x| x * 2 }
      allow(mock_processor).to receive(:map).and_return([4])

      recipe = ApiClient::Transforms::Recipe.default
      errors = ApiClient::Processing::ErrorStrategy.skip
      opts = {recipe: recipe, errors: errors, block: block}
      result = described_class.execute_with_processor(mock_processor_class, opts, [double])

      expect(result).to eq([4])
    end
  end
end
