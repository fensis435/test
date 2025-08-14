require 'rails_helper'

RSpec.describe UserSession, type: :model do
  let(:user) { create(:user) }
  let(:jti) { SecureRandom.uuid }
  let(:exp) { 1.hour.from_now.to_i }

  describe 'validations' do
    it 'requires valid token_type' do
      session = UserSession.new(user: user, jti: jti, exp: exp, token_type: 'invalid')
      expect(session).not_to be_valid
      expect(session.errors[:token_type]).to include("is not included in the list")
    end

    it 'accepts valid token_types' do
      %w[access refresh].each do |type|
        session = UserSession.new(user: user, jti: jti, exp: exp, token_type: type)
        expect(session).to be_valid
      end
    end
  end

  describe '#expired?' do
    it 'returns true for expired session' do
      expired_session = UserSession.new(user: user, jti: jti, exp: 1.hour.ago.to_i, token_type: 'access')
      expect(expired_session.expired?).to be true
    end

    it 'returns false for active session' do
      active_session = UserSession.new(user: user, jti: jti, exp: exp, token_type: 'access')
      expect(active_session.expired?).to be false
    end
  end
end
