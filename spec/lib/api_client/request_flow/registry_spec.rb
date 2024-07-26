require "spec_helper"
require "api_client"

RSpec.describe ApiClient::RequestFlow::Registry do
  describe ".processor?" do
    it "returns true for registered processors" do
      expect(described_class.processor?(:parallel_map)).to be true
      expect(described_class.processor?(:async_map)).to be true
      expect(described_class.processor?(:concurrent_map)).to be true
    end

    it "returns false for unregistered processors" do
      expect(described_class.processor?(:unknown_map)).to be false
    end
  end

  describe ".processor" do
    it "returns RactorProcessor for :parallel_map" do
      expect(described_class.processor(:parallel_map)).to eq(ApiClient::Processing::RactorProcessor)
    end

    it "returns AsyncProcessor for :async_map" do
      expect(described_class.processor(:async_map)).to eq(ApiClient::Processing::AsyncProcessor)
    end

    it "returns ConcurrentProcessor for :concurrent_map" do
      expect(described_class.processor(:concurrent_map))
        .to eq(ApiClient::Processing::ConcurrentProcessor)
    end
  end

  describe ".processor_keys" do
    it "includes all registered processor keys" do
      keys = described_class.processor_keys
      expect(keys).to include(:parallel_map)
      expect(keys).to include(:async_map)
      expect(keys).to include(:concurrent_map)
    end
  end

  describe ".register_processor" do
    it "allows registering custom processors" do
      custom_processor = Class.new
      described_class.register_processor(:custom_map) { custom_processor }

      expect(described_class.processor?(:custom_map)).to be true
      expect(described_class.processor(:custom_map)).to eq(custom_processor)
    end
  end

  describe ".register_adapter" do
    it "registers an adapter for later lookup" do
      custom_adapter = Class.new
      described_class.register_adapter(:custom_http) { custom_adapter }

      expect(described_class.adapter?(:custom_http)).to be true
      expect(described_class.adapter(:custom_http)).to eq(custom_adapter)
    end
  end

  describe ".adapter?" do
    it "returns true for registered adapters" do
      unless described_class.adapter?(:adapter_check)
        described_class.register_adapter(:adapter_check) { Class.new }
      end
      expect(described_class.adapter?(:adapter_check)).to be true
    end

    it "returns false for unregistered adapters" do
      expect(described_class.adapter?(:nonexistent_adapter)).to be false
    end
  end

  describe ".adapter" do
    it "returns the registered adapter class" do
      adapter_class = Class.new
      unless described_class.adapter?(:lookup_adapter)
        described_class.register_adapter(:lookup_adapter) { adapter_class }
      end
      expect(described_class.adapter(:lookup_adapter)).to eq(adapter_class)
    end
  end

  describe ".adapter_keys" do
    it "includes registered adapter keys" do
      unless described_class.adapter?(:keys_adapter)
        described_class.register_adapter(:keys_adapter) { Class.new }
      end
      expect(described_class.adapter_keys).to include(:keys_adapter)
    end

    it "returns symbols" do
      expect(described_class.adapter_keys).to all(be_a(Symbol))
    end
  end
end
