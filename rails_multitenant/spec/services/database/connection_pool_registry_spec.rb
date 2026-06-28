require "rails_helper"

RSpec.describe DatabaseSwitcher::ConnectionPoolRegistry do
  subject(:registry) { described_class.new }

  let(:db_config_a) do
    Domain::Tenant::DatabaseConfig.for_aws(tenant_slug: "tenant-a", rds_host: "host-a.example.com")
  end

  let(:db_config_b) do
    Domain::Tenant::DatabaseConfig.for_aws(tenant_slug: "tenant-b", rds_host: "host-b.example.com")
  end

  let(:mock_pool) { instance_double(ConnectionPool) }

  before do
    allow(ConnectionPool).to receive(:new).and_return(mock_pool)
    allow(mock_pool).to receive(:with_connection).and_yield(double("connection", verify!: true, disconnect!: nil))
    allow(mock_pool).to receive(:shutdown)
    # Stub ActiveRecord establish_connection to avoid real DB calls
    allow(ActiveRecord::Base).to receive(:establish_connection).and_return(
      double("pool", connection: double("conn", verify!: true))
    )
  end

  describe "#fetch_or_create" do
    it "creates a new pool for a new config" do
      registry.fetch_or_create(db_config_a)
      expect(ConnectionPool).to have_received(:new).once
    end

    it "returns the same pool on subsequent calls for same config" do
      pool1 = registry.fetch_or_create(db_config_a)
      pool2 = registry.fetch_or_create(db_config_a)
      expect(pool1).to eq(pool2)
      expect(ConnectionPool).to have_received(:new).once
    end

    it "creates separate pools for different configs" do
      registry.fetch_or_create(db_config_a)
      registry.fetch_or_create(db_config_b)
      expect(ConnectionPool).to have_received(:new).twice
    end
  end

  describe "#pool_count" do
    it "returns 0 initially" do
      expect(registry.pool_count).to eq(0)
    end

    it "returns the number of active pools" do
      registry.fetch_or_create(db_config_a)
      registry.fetch_or_create(db_config_b)
      expect(registry.pool_count).to eq(2)
    end
  end

  describe "#invalidate" do
    before { registry.fetch_or_create(db_config_a) }

    it "removes the pool" do
      registry.invalidate(db_config_a)
      expect(registry.pool_count).to eq(0)
    end

    it "shuts down the pool" do
      registry.invalidate(db_config_a)
      expect(mock_pool).to have_received(:shutdown)
    end

    it "creates a new pool on next fetch after invalidation" do
      registry.invalidate(db_config_a)
      registry.fetch_or_create(db_config_a)
      expect(ConnectionPool).to have_received(:new).twice
    end
  end

  describe "#stats" do
    before do
      registry.fetch_or_create(db_config_a)
      registry.fetch_or_create(db_config_b)
    end

    it "returns stats hash with total_pools" do
      stats = registry.stats
      expect(stats[:total_pools]).to eq(2)
    end

    it "includes pool key prefixes" do
      stats = registry.stats
      expect(stats[:pool_keys]).to include("host-a.example.com", "host-b.example.com")
    end
  end
end
