require "spec_helper"
require "api_client/transforms"
require "api_client/processing/ractor_pool"

RSpec.describe "RactorPool transform parity with Transforms::REGISTRY",
  skip: !defined?(Ractor::Port) && "Ractor::Port requires Ruby 4.0+" do
  subject(:pool) { ApiClient::Processing::RactorPool.new(size: 2) }

  after { pool.shutdown }

  # The RactorPool inlines transform logic inside the Ractor block because
  # Ractors have isolated memory and cannot access the parent's
  # Transforms::REGISTRY. This test ensures the inlined transforms produce
  # identical results to the canonical Transforms module.
  #
  # If you add a transform to Transforms::REGISTRY, add it to the Ractor
  # worker loop in RactorPool#create_worker AND add a case here.

  ApiClient::Transforms::REGISTRY.each_key do |transform_name|
    describe ":#{transform_name} transform" do
      let(:test_data) { test_input_for(transform_name) }

      it "produces the same result as Transforms.apply" do
        expected = ApiClient::Transforms.apply(transform_name, test_data)

        results, errors = pool.process(
          [test_data],
          extractor: ->(item) { item },
          transform: transform_name
        )

        expect(errors).to be_empty,
          "RactorPool returned errors for :#{transform_name}: #{errors.inspect}"
        expect(results.first).to eq(expected),
          "RactorPool :#{transform_name} result differs from Transforms.apply"
      end
    end
  end

  it "supports every transform registered in Transforms::REGISTRY" do
    registry_keys = ApiClient::Transforms::REGISTRY.keys.sort
    # The RactorPool worker case statement must handle all of these.
    # If this test fails, a new transform was added to REGISTRY but not
    # to the Ractor worker loop in RactorPool#create_worker.
    registry_keys.each do |key|
      expect {
        pool.process(
          [test_input_for(key)],
          extractor: ->(item) { item },
          transform: key
        )
      }.not_to raise_error, "RactorPool does not support transform :#{key}"
    end
  end

  private

  def test_input_for(transform_name)
    case transform_name
    when :json then '{"key":"value"}'
    when :sha256 then "hello world"
    when :identity then "passthrough"
    else "test data"
    end
  end
end
