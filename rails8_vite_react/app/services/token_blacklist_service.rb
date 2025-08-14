class TokenBlacklistService
  def self.blacklist_token(jti, exp, user_id = nil)
    BlacklistedToken.blacklist_token(jti, exp, user_id)
    
    # セッションテーブルからも削除
    UserSession.where(jti: jti).destroy_all
  end

  def self.blacklisted?(jti)
    return false if jti.blank?
    BlacklistedToken.blacklisted?(jti)
  end

  def self.blacklist_user_all_tokens(user_id)
    user = User.find(user_id)
    current_time = Time.current.to_i
    
    # ユーザーのアクティブなセッションを取得してブラックリストに追加
    user.user_sessions.active.find_each do |session|
      BlacklistedToken.blacklist_token(session.jti, session.exp, user_id)
    end
    
    # ユーザーのすべてのセッションを削除
    user.user_sessions.destroy_all
    
    # ユーザーのlogout_atを更新（この時間以前に発行されたトークンは無効）
    user.update!(logout_at: current_time)
  end

  def self.user_logged_out_before?(user_id, token_issued_at)
    user = User.find_by(id: user_id)
    return false unless user&.logout_at
    
    token_issued_at < user.logout_at
  end

  # 期限切れトークンのクリーンアップ
  def self.cleanup_expired_tokens
    BlacklistedToken.cleanup_expired
    UserSession.cleanup_expired
  end
end
