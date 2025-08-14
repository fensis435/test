RSpec.describe BlacklistedToken, type: :model do
  let(:user) { create(:user) }
  let(:jti) { SecureRandom.uuid }
  let(:exp) { 1.hour.from_now.to_i }

  describe 'validations' do
    it 'requires jti' do
      token = BlacklistedToken.new(exp: exp, user: user)
      expect(token).not_to be_valid
      expect(token.errors[:jti]).to include("can't be blank")
    end

    it 'requires unique jti' do
      BlacklistedToken.create!(jti: jti, exp: exp, user: user)
      duplicate = BlacklistedToken.new(jti: jti, exp: exp, user: user)
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:jti]).to include("has already been taken")
    end
  end

  describe '.blacklisted?' do
    it 'returns true for blacklisted active token' do
      BlacklistedToken.create!(jti: jti, exp: exp, user: user)
      expect(BlacklistedToken.blacklisted?(jti)).to be true
    end

    it 'returns false for expired blacklisted token' do
      expired_exp = 1.hour.ago.to_i
      BlacklistedToken.create!(jti: jti, exp: expired_exp, user: user)
      expect(BlacklistedToken.blacklisted?(jti)).to be false
    end

    it 'returns false for non-blacklisted token' do
      expect(BlacklistedToken.blacklisted?('non-existent')).to be false
    end
  end

  describe '.cleanup_expired' do
    it 'removes expired tokens' do
      expired_jti = SecureRandom.uuid
      expired_exp = 1.hour.ago.to_i
      
      BlacklistedToken.create!(jti: expired_jti, exp: expired_exp, user: user)
      BlacklistedToken.create!(jti: jti, exp: exp, user: user)
      
      expect { BlacklistedToken.cleanup_expired }.to change(BlacklistedToken, :count).by(-1)
      expect(BlacklistedToken.exists?(jti: expired_jti)).to be false
      expect(BlacklistedToken.exists?(jti: jti)).to be true
    end
  end
end
