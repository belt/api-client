require "spec_helper"
require "api_client"

RSpec.describe ApiClient::Concerns::Poolable do
  let(:pool_config) { ApiClient::PoolConfig.new }
  let(:test_class) do
    Class.new do
      include ApiClient::Concerns::Poolable

      attr_reader :pool

      def initialize(pool_config, &factory)
        @pool = build_pool(pool_config, &factory)
      end

      def checkout(&block)
        with_pooled_connection(&block)
      end
    end
  end

  describe "#build_pool" do
    context "when pooling is enabled" do
      it "returns a ConnectionPool" do
        instance = test_class.new(pool_config) { Object.new }
        expect(instance.pool).to be_a(ConnectionPool)
      end

      it "respects configured size" do
        pool_config.size = 3
        instance = test_class.new(pool_config) { Object.new }
        expect(instance.pool.size).to eq(3)
      end
    end

    context "when pooling is disabled" do
      before { pool_config.enabled = false }

      it "returns a NullPool" do
        instance = test_class.new(pool_config) { Object.new }
        expect(instance.pool).to be_a(ApiClient::Concerns::NullPool)
      end
    end
  end

  describe "#with_pooled_connection" do
    it "yields a connection from the pool" do
      conn = Object.new
      instance = test_class.new(pool_config) { conn }

      instance.checkout do |checked_out|
        expect(checked_out).to equal(conn)
      end
    end

    it "returns the block result" do
      instance = test_class.new(pool_config) { Object.new }
      result = instance.checkout { 42 }
      expect(result).to eq(42)
    end
  end

  describe ApiClient::Concerns::NullPool do
    subject(:pool) { described_class.new { connection } }

    let(:connection) { Object.new }

    describe "#with" do
      it "yields the single instance" do
        pool.with do |conn|
          expect(conn).to equal(connection)
        end
      end

      it "returns the block result" do
        result = pool.with { "result" }
        expect(result).to eq("result")
      end

      it "always yields the same instance" do
        ids = []
        3.times { pool.with { |c| ids << c.object_id } }
        expect(ids.uniq.size).to eq(1)
      end
    end

    describe "#size" do
      it "returns 1" do
        expect(pool.size).to eq(1)
      end
    end

    describe "#available" do
      it "returns 1" do
        expect(pool.available).to eq(1)
      end
    end

    describe "#shutdown" do
      it "is a no-op" do
        expect { pool.shutdown }.not_to raise_error
      end
    end

    describe "#reload" do
      it "is a no-op" do
        expect { pool.reload }.not_to raise_error
      end
    end
  end
end
