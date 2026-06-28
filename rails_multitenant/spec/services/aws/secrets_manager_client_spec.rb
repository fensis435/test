require "rails_helper"

RSpec.describe Services::Aws::SecretsManagerClient do
  subject(:client) { described_class.new(region: "ap-northeast-1") }

  let(:aws_client) { instance_double(Aws::SecretsManager::Client) }

  before do
    stub_const("Aws::SecretsManager::Client", Class.new do
      def initialize(**); end
    end)
    allow(Aws::SecretsManager::Client).to receive(:new).and_return(aws_client)
  end

  describe "#store_tenant_credential" do
    context "when secret does not exist" do
      before do
        allow(aws_client).to receive(:create_secret).and_return(
          double("response", arn: "arn:aws:secretsmanager:ap-northeast-1:123:secret:test")
        )
      end

      it "creates the secret and returns true" do
        result = client.store_tenant_credential(username: "tenant_user", password: "s3cr3t")
        expect(result).to be(true)
        expect(aws_client).to have_received(:create_secret).with(
          hash_including(name: "multitenant/tenant-credentials/tenant_user")
        )
      end
    end

    context "when secret already exists" do
      before do
        allow(aws_client).to receive(:create_secret).and_raise(
          Aws::SecretsManager::Errors::ResourceExistsException.new(nil, "already exists")
        )
        allow(aws_client).to receive(:put_secret_value).and_return(
          double("response", version_id: "v2")
        )
      end

      it "updates the existing secret and returns true" do
        result = client.store_tenant_credential(username: "tenant_user", password: "new-s3cr3t")
        expect(result).to be(true)
        expect(aws_client).to have_received(:put_secret_value).with(
          hash_including(secret_id: "multitenant/tenant-credentials/tenant_user")
        )
      end
    end

    context "when AWS raises a ServiceError" do
      before do
        allow(aws_client).to receive(:create_secret).and_raise(
          Aws::SecretsManager::Errors::ServiceError.new(nil, "service unavailable")
        )
      end

      it "returns false" do
        result = client.store_tenant_credential(username: "tenant_user", password: "s3cr3t")
        expect(result).to be(false)
      end
    end
  end

  describe "#fetch_tenant_credential" do
    context "when secret exists" do
      before do
        allow(aws_client).to receive(:get_secret_value).and_return(
          double("response", secret_string: { username: "tenant_user", password: "s3cr3t" }.to_json)
        )
      end

      it "returns the password" do
        password = client.fetch_tenant_credential(username: "tenant_user")
        expect(password).to eq("s3cr3t")
      end
    end

    context "when secret does not exist" do
      before do
        allow(aws_client).to receive(:get_secret_value).and_raise(
          Aws::SecretsManager::Errors::ResourceNotFoundException.new(nil, "not found")
        )
      end

      it "returns nil" do
        expect(client.fetch_tenant_credential(username: "unknown_user")).to be_nil
      end
    end
  end

  describe "#delete_tenant_credential" do
    context "when secret exists" do
      before do
        allow(aws_client).to receive(:delete_secret).and_return(double("response"))
      end

      it "schedules deletion and returns true" do
        result = client.delete_tenant_credential(username: "tenant_user")
        expect(result).to be(true)
        expect(aws_client).to have_received(:delete_secret).with(
          hash_including(
            secret_id: "multitenant/tenant-credentials/tenant_user",
            recovery_window_in_days: 7
          )
        )
      end
    end

    context "when secret does not exist" do
      before do
        allow(aws_client).to receive(:delete_secret).and_raise(
          Aws::SecretsManager::Errors::ResourceNotFoundException.new(nil, "not found")
        )
      end

      it "returns true (idempotent)" do
        expect(client.delete_tenant_credential(username: "unknown_user")).to be(true)
      end
    end
  end
end
