require "rails_helper"

RSpec.describe Services::Database::RdsIamAuthenticator do
  subject(:authenticator) { described_class.new(region: "ap-northeast-1") }

  describe "#generate_token" do
    let(:host) { "rds.example.com" }
    let(:port) { 5432 }
    let(:username) { "tenant_user" }
    let(:mock_token) { "mock-iam-token-#{SecureRandom.hex(8)}" }
    let(:mock_signer) { instance_double(Aws::RDS::AuthTokenGenerator) }

    before do
      stub_const("Aws::RDS::AuthTokenGenerator", Class.new do
        def initialize(**); end
        def auth_token(**); "mock-iam-token"; end
      end)
    end

    it "returns an auth token" do
      token = authenticator.generate_token(host: host, port: port, username: username)
      expect(token).to be_a(String)
      expect(token).not_to be_empty
    end

    it "caches the token on subsequent calls" do
      call_count = 0
      allow_any_instance_of(Aws::RDS::AuthTokenGenerator).to receive(:auth_token) do
        call_count += 1
        "token-#{call_count}"
      end

      first = authenticator.generate_token(host: host, port: port, username: username)
      second = authenticator.generate_token(host: host, port: port, username: username)
      expect(first).to eq(second)
      expect(call_count).to eq(1)
    end

    it "fetches a new token after cache expiry" do
      call_count = 0
      allow_any_instance_of(Aws::RDS::AuthTokenGenerator).to receive(:auth_token) do
        call_count += 1
        "token-#{call_count}"
      end

      authenticator.generate_token(host: host, port: port, username: username)

      Timecop.travel(Services::Database::RdsIamAuthenticator::TOKEN_TTL) do
        authenticator.generate_token(host: host, port: port, username: username)
      end

      expect(call_count).to eq(2)
    end

    it "generates separate tokens for different users" do
      tokens = []
      allow_any_instance_of(Aws::RDS::AuthTokenGenerator).to receive(:auth_token) do |_, **args|
        "token-for-#{args[:user_name]}"
      end

      tokens << authenticator.generate_token(host: host, port: port, username: "user_a")
      tokens << authenticator.generate_token(host: host, port: port, username: "user_b")
      expect(tokens.uniq.length).to eq(2)
    end
  end
end
