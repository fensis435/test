require "rails_helper"

RSpec.describe Services::Auth::JwksCache do
  subject(:cache) { described_class.new(http_client: http_client) }

  let(:http_client) { instance_double("HttpClient") }
  let(:jwks_uri) { "https://cognito-idp.ap-northeast-1.amazonaws.com/pool/.well-known/jwks.json" }
  let(:jwks_data) { { "keys" => [{ "kid" => "key-1", "kty" => "RSA" }] } }

  let(:mock_response) do
    resp = instance_double("Net::HTTPResponse")
    allow(resp).to receive(:body).and_return(jwks_data.to_json)
    resp
  end

  describe "#fetch" do
    context "on first call" do
      before do
        allow(http_client).to receive(:get).with(jwks_uri).and_return(mock_response)
      end

      it "fetches from remote" do
        result = cache.fetch(jwks_uri)
        expect(result).to eq(jwks_data)
        expect(http_client).to have_received(:get).once
      end
    end

    context "on subsequent calls within TTL" do
      before do
        allow(http_client).to receive(:get).and_return(mock_response)
        cache.fetch(jwks_uri)
      end

      it "returns cached data without fetching again" do
        cache.fetch(jwks_uri)
        expect(http_client).to have_received(:get).once
      end
    end

    context "when cache entry is expired" do
      before do
        allow(http_client).to receive(:get).and_return(mock_response)
        cache.fetch(jwks_uri)
      end

      it "re-fetches from remote after TTL" do
        Timecop.travel(Services::Auth::JwksCache::TTL + 1) do
          cache.fetch(jwks_uri)
        end
        expect(http_client).to have_received(:get).twice
      end
    end

    context "when remote fetch fails" do
      before do
        allow(http_client).to receive(:get).and_raise(StandardError, "Connection refused")
      end

      it "returns nil" do
        expect(cache.fetch(jwks_uri)).to be_nil
      end
    end
  end

  describe "#invalidate" do
    before do
      allow(http_client).to receive(:get).and_return(mock_response)
      cache.fetch(jwks_uri)
    end

    context "with specific URI" do
      it "clears the entry and re-fetches on next call" do
        cache.invalidate(jwks_uri)
        cache.fetch(jwks_uri)
        expect(http_client).to have_received(:get).twice
      end
    end

    context "without URI argument" do
      it "clears all entries" do
        cache.invalidate
        cache.fetch(jwks_uri)
        expect(http_client).to have_received(:get).twice
      end
    end
  end
end
