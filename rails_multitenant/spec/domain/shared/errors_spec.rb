require "rails_helper"

RSpec.describe Domain::Shared::Errors do
  shared_examples "a base error" do |error_class, default_code|
    it "is a StandardError" do
      expect(error_class.ancestors).to include(StandardError)
    end

    it "has a code attribute" do
      error = error_class.new("test message")
      expect(error.code).to eq(default_code)
    end

    it "has a message" do
      error = error_class.new("test message")
      expect(error.message).to eq("test message")
    end
  end

  describe Domain::Shared::Errors::ValidationError do
    include_examples "a base error", described_class, "VALIDATION_ERROR"

    it "accepts details" do
      error = described_class.new("Failed", details: ["Field required"])
      expect(error.details).to eq(["Field required"])
    end
  end

  describe Domain::Shared::Errors::NotFoundError do
    it "formats message with resource and identifier" do
      error = described_class.new("Tenant", "acme-corp")
      expect(error.message).to eq("Tenant not found: acme-corp")
    end

    it "has NOT_FOUND code" do
      error = described_class.new("Tenant", "x")
      expect(error.code).to eq("NOT_FOUND")
    end
  end

  describe Domain::Shared::Errors::TenantNotFoundError do
    it "formats message with tenant identifier" do
      error = described_class.new("acme-corp")
      expect(error.message).to eq("Tenant not found: acme-corp")
    end
  end

  describe Domain::Shared::Errors::TenantSuspendedError do
    it "includes slug in message" do
      error = described_class.new("acme-corp")
      expect(error.message).to include("acme-corp")
    end

    it "has TENANT_SUSPENDED code" do
      error = described_class.new("acme-corp")
      expect(error.code).to eq("TENANT_SUSPENDED")
    end
  end

  describe Domain::Shared::Errors::TokenExpiredError do
    it "has TOKEN_EXPIRED code" do
      error = described_class.new
      expect(error.code).to eq("TOKEN_EXPIRED")
    end
  end

  describe Domain::Shared::Errors::TokenVerificationError do
    it "has TOKEN_VERIFICATION_FAILED code" do
      error = described_class.new("bad signature")
      expect(error.code).to eq("TOKEN_VERIFICATION_FAILED")
    end
  end

  describe Domain::Shared::Errors::InvalidStateTransitionError do
    it "has INVALID_STATE_TRANSITION code" do
      error = described_class.new("Cannot activate terminated tenant")
      expect(error.code).to eq("INVALID_STATE_TRANSITION")
    end
  end

  describe Domain::Shared::Errors::ConflictError do
    it "has CONFLICT code" do
      error = described_class.new("Slug already taken")
      expect(error.code).to eq("CONFLICT")
    end
  end

  describe Domain::Shared::Errors::DatabaseConnectionError do
    it "has DATABASE_CONNECTION_ERROR code" do
      error = described_class.new("Cannot connect")
      expect(error.code).to eq("DATABASE_CONNECTION_ERROR")
    end
  end

  describe Domain::Shared::Errors::TenantProvisioningError do
    it "has TENANT_PROVISIONING_ERROR code" do
      error = described_class.new("Provisioning failed")
      expect(error.code).to eq("TENANT_PROVISIONING_ERROR")
    end
  end

  describe Domain::Shared::Errors::UnauthorizedError do
    it "has UNAUTHORIZED code" do
      error = described_class.new
      expect(error.code).to eq("UNAUTHORIZED")
    end

    it "has default message" do
      expect(described_class.new.message).to eq("Unauthorized")
    end
  end

  describe Domain::Shared::Errors::ForbiddenError do
    it "has FORBIDDEN code" do
      expect(described_class.new.code).to eq("FORBIDDEN")
    end
  end
end
