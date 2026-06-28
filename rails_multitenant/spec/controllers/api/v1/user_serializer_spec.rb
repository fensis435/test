require "rails_helper"

RSpec.describe Serializers::UserSerializer do
  let(:user) { create(:user_record, email: "john@example.com", display_name: "John Doe", role: "admin") }
  subject(:serialized) { described_class.new(user).as_json }

  it "includes id" do
    expect(serialized[:id]).to eq(user.id)
  end

  it "includes cognito_sub" do
    expect(serialized[:cognito_sub]).to eq(user.cognito_sub)
  end

  it "includes email" do
    expect(serialized[:email]).to eq("john@example.com")
  end

  it "includes display_name" do
    expect(serialized[:display_name]).to eq("John Doe")
  end

  it "includes role" do
    expect(serialized[:role]).to eq("admin")
  end

  it "includes active status" do
    expect(serialized[:active]).to be(true)
  end

  it "includes created_at as ISO8601" do
    expect(serialized[:created_at]).to match(/\d{4}-\d{2}-\d{2}T/)
  end

  it "includes updated_at as ISO8601" do
    expect(serialized[:updated_at]).to match(/\d{4}-\d{2}-\d{2}T/)
  end

  context "when user is deactivated" do
    let(:user) { create(:user_record, :deactivated) }

    it "active is false" do
      expect(serialized[:active]).to be(false)
    end
  end
end
