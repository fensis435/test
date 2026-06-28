RSpec.shared_examples "requires authentication" do
  context "when no Authorization header is present" do
    before { headers.delete("Authorization") }

    it "returns 401 Unauthorized" do
      subject
      expect(response).to have_http_status(:unauthorized)
      expect(json_body[:error][:code]).to eq("UNAUTHORIZED")
    end
  end

  context "when an invalid token is provided" do
    before do
      stub_cognito_verification(success: false)
    end

    it "returns 401 Unauthorized" do
      subject
      expect(response).to have_http_status(:unauthorized)
    end
  end
end

RSpec.shared_examples "requires admin role" do
  context "when user is not admin" do
    before do
      headers.merge!(auth_headers(role: "member"))
    end

    it "returns 403 Forbidden" do
      subject
      expect(response).to have_http_status(:forbidden)
      expect(json_body[:error][:code]).to eq("FORBIDDEN")
    end
  end
end

RSpec.shared_examples "returns paginated response" do
  it "includes pagination metadata" do
    subject
    expect(json_body[:meta]).to include(
      :current_page,
      :per_page,
      :total_count,
      :total_pages
    )
  end
end

RSpec.shared_examples "returns not found" do
  it "returns 404 Not Found" do
    subject
    expect(response).to have_http_status(:not_found)
    expect(json_body[:error][:code]).to eq("NOT_FOUND")
  end
end

RSpec.shared_examples "a successful response" do |status: :ok|
  it "returns #{status}" do
    subject
    expect(response).to have_http_status(status)
  end

  it "returns JSON content type" do
    subject
    expect(response.content_type).to match(%r{application/json})
  end
end
