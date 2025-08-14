require 'rails_helper'

RSpec.describe TokenBlacklistService do
  let(:user) { create(:user) }
  let(:jti) { SecureRandom.uuid }
  let(:exp) { 1.hour.from_now.to_i }

  describe '.blacklist_token' do
    it 'adds token to blacklist' do
      TokenBlacklistService.blacklist_token(jti, exp, user.id)
      expect(TokenBlacklistService.blacklisted?(jti)).to be true
    end

    it 'removes session when token is blacklisted' do
      session = user.user_sessions.create!(jti: jti, token_type: 'access', exp: exp)
      TokenBlacklistService.blacklist_token(jti, exp, user.id)
      expect(UserSession.exists?(jti: jti)).to be false
    end
  end

  describe '.blacklist_user_all_tokens' do
    it 'blacklists all user tokens and updates logout_at' do
      # ユーザーのセッションを作成
      session1 = user.user_sessions.create!(jti: SecureRandom.uuid, token_type: 'access', exp: exp)
      session2 = user.user_sessions.create!(jti: SecureRandom.uuid, token_type: 'refresh', exp: exp)
      
      TokenBlacklistService.blacklist_user_all_tokens(user.id)
      
      expect(user.reload.logout_at).to be_present
      expect(user.user_sessions.count).to eq(0)
      expect(TokenBlacklistService.blacklisted?(session1.jti)).to be true
      expect(TokenBlacklistService.blacklisted?(session2.jti)).to be true
    end
  end
end
