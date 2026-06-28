require "rails_helper"

RSpec.describe Services::Auth::CognitoJwtVerifier do
  subject(:verifier) do
    described_class.new(
      user_pool_id: "ap-northeast-1_TestPool",
      region: "ap-northeast-1",
      jwks_cache: jwks_cache
    )
  end

  let(:jwks_cache) { instance_double(Services::Auth::JwksCache) }
  let(:rsa_key) { OpenSSL::PKey::RSA.generate(2048) }
  let(:kid) { "test-key-id" }

  let(:jwk_hash) do
    {
      "kty" => "RSA",
      "kid" => kid,
      "use" => "sig",
      "alg" => "RS256",
      "n" => Base64.urlsafe_encode64(rsa_key.public_key.n.to_s(2), padding: false),
      "e" => Base64.urlsafe_encode64(rsa_key.public_key.e.to_s(2), padding: false)
    }
  end

  let(:jwks_response) { { "keys" => [jwk_hash] } }

  let(:valid_payload) do
    {
      "sub" => SecureRandom.uuid,
      "email" => "user@example.com",
      "custom:tenant_slug" => "acme-corp",
      "custom:role" => "admin",
      "cognito:groups" => [],
      "token_use" => "id",
      "iss" => "https://cognito-idp.ap-northeast-1.amazonaws.com/ap-northeast-1_TestPool",
      "iat" => Time.current.to_i,
      "exp" => 1.hour.from_now.to_i
    }
  end

  def encode_token(payload, key = rsa_key, headers = { kid: kid })
    JWT.encode(payload, key, "RS256", headers)
  end

  before do
    allow(jwks_cache).to receive(:fetch).and_return(jwks_response)
  end

  describe "#verify" do
    context "with a valid token" do
      it "returns Success with the payload" do
        token = encode_token(valid_payload)
        result = verifier.verify(token)
        expect(result).to be_success
        expect(result.value!["sub"]).to eq(valid_payload["sub"])
        expect(result.value!["email"]).to eq("user@example.com")
      end
    end

    context "with a blank token" do
      it "returns Failure with TokenVerificationError" do
        result = verifier.verify("")
        expect(result).to be_failure
        expect(result.failure).to be_a(Domain::Shared::Errors::TokenVerificationError)
      end

      it "returns Failure for nil token" do
        result = verifier.verify(nil)
        expect(result).to be_failure
      end
    end

    context "with an expired token" do
      it "returns Failure with TokenExpiredError" do
        expired_payload = valid_payload.merge("exp" => 1.hour.ago.to_i)
        token = encode_token(expired_payload)
        result = verifier.verify(token)
        expect(result).to be_failure
        expect(result.failure).to be_a(Domain::Shared::Errors::TokenExpiredError)
      end
    end

    context "with a wrong issuer" do
      it "returns Failure" do
        bad_payload = valid_payload.merge(
          "iss" => "https://cognito-idp.us-east-1.amazonaws.com/us-east-1_WrongPool"
        )
        token = encode_token(bad_payload)
        result = verifier.verify(token)
        expect(result).to be_failure
        expect(result.failure).to be_a(Domain::Shared::Errors::TokenVerificationError)
      end
    end

    context "with an unknown key id" do
      it "returns Failure" do
        token = encode_token(valid_payload, rsa_key, { kid: "unknown-kid" })
        result = verifier.verify(token)
        expect(result).to be_failure
        expect(result.failure.message).to include("No matching JWK")
      end
    end

    context "with a tampered token" do
      it "returns Failure" do
        token = encode_token(valid_payload)
        parts = token.split(".")
        tampered = "#{parts[0]}.#{Base64.urlsafe_encode64("{\"sub\":\"hacked\"}", padding: false)}.#{parts[2]}"
        result = verifier.verify(tampered)
        expect(result).to be_failure
      end
    end

    context "with missing required claims" do
      it "returns Failure when sub is missing" do
        payload = valid_payload.except("sub")
        token = encode_token(payload)
        result = verifier.verify(token)
        expect(result).to be_failure
        expect(result.failure.message).to include("Missing sub claim")
      end

      it "returns Failure when email is missing" do
        payload = valid_payload.except("email")
        token = encode_token(payload)
        result = verifier.verify(token)
        expect(result).to be_failure
        expect(result.failure.message).to include("Missing email claim")
      end
    end

    context "when JWKS fetch fails" do
      before do
        allow(jwks_cache).to receive(:fetch).and_return(nil)
      end

      it "returns Failure" do
        token = encode_token(valid_payload)
        result = verifier.verify(token)
        expect(result).to be_failure
      end
    end

    context "with a signed-by-wrong-key token" do
      it "returns Failure" do
        wrong_key = OpenSSL::PKey::RSA.generate(2048)
        token = encode_token(valid_payload, wrong_key, { kid: kid })
        result = verifier.verify(token)
        expect(result).to be_failure
      end
    end
  end
end
