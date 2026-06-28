require "rails_helper"

RSpec.describe Services::Database::DatabaseProvisioner do
  subject(:provisioner) do
    described_class.new(
      platform: platform,
      aws_provisioner: aws_provisioner,
      onprem_provisioner: onprem_provisioner,
      logger: logger
    )
  end

  let(:aws_provisioner)    { instance_double(Services::Database::AwsRdsProvisioner) }
  let(:onprem_provisioner) { instance_double(Services::Database::OnpremPostgresProvisioner) }
  let(:logger)             { instance_double(ActiveSupport::Logger, info: nil, debug: nil, error: nil) }

  let(:tenant) do
    Domain::Tenant::Tenant.new(
      id: SecureRandom.uuid,
      slug: "acme-corp",
      name: "Acme Corp",
      status: "provisioning",
      plan: "professional",
      created_at: 1.hour.ago,
      updated_at: 1.hour.ago
    )
  end

  let(:db_config) do
    Domain::Tenant::DatabaseConfig.for_aws(tenant_slug: "acme-corp", rds_host: "localhost")
  end

  describe "#provision" do
    context "on AWS platform" do
      let(:platform) { "aws" }

      before do
        allow(aws_provisioner).to receive(:provision).and_return(Success(db_config))
      end

      it "delegates to aws_provisioner" do
        provisioner.provision(tenant, db_config)
        expect(aws_provisioner).to have_received(:provision).with(tenant, db_config)
      end

      it "does not call onprem_provisioner" do
        provisioner.provision(tenant, db_config)
        expect(onprem_provisioner).not_to have_received(:provision)
      end

      it "returns the aws_provisioner result" do
        result = provisioner.provision(tenant, db_config)
        expect(result).to be_success
      end
    end

    context "on on-prem platform" do
      let(:platform) { "onprem" }
      let(:onprem_config) do
        Domain::Tenant::DatabaseConfig.for_onprem(tenant_slug: "acme-corp", namespace: "default")
      end

      before do
        allow(onprem_provisioner).to receive(:provision).and_return(Success(onprem_config))
      end

      it "delegates to onprem_provisioner" do
        provisioner.provision(tenant, onprem_config)
        expect(onprem_provisioner).to have_received(:provision).with(tenant, onprem_config)
      end

      it "does not call aws_provisioner" do
        provisioner.provision(tenant, onprem_config)
        expect(aws_provisioner).not_to have_received(:provision)
      end
    end

    context "with unknown platform" do
      let(:platform) { "gcp" }

      it "returns Failure with DatabaseConnectionError" do
        result = provisioner.provision(tenant, db_config)
        expect(result).to be_failure
        expect(result.failure).to be_a(Domain::Shared::Errors::DatabaseConnectionError)
        expect(result.failure.message).to include("Unknown platform")
      end
    end

    context "when provisioner returns Failure" do
      let(:platform) { "aws" }

      before do
        allow(aws_provisioner).to receive(:provision).and_return(
          Failure(Domain::Shared::Errors::TenantProvisioningError.new("RDS error"))
        )
      end

      it "propagates the Failure" do
        result = provisioner.provision(tenant, db_config)
        expect(result).to be_failure
        expect(result.failure.message).to eq("RDS error")
      end
    end
  end

  describe "#deprovision" do
    context "on AWS platform" do
      let(:platform) { "aws" }

      before do
        allow(aws_provisioner).to receive(:deprovision).and_return(Success(true))
      end

      it "delegates to aws_provisioner" do
        provisioner.deprovision(tenant)
        expect(aws_provisioner).to have_received(:deprovision).with(tenant)
      end
    end

    context "on on-prem platform" do
      let(:platform) { "onprem" }

      before do
        allow(onprem_provisioner).to receive(:deprovision).and_return(Success(true))
      end

      it "delegates to onprem_provisioner" do
        provisioner.deprovision(tenant)
        expect(onprem_provisioner).to have_received(:deprovision).with(tenant)
      end
    end
  end
end
