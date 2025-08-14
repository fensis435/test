class AuthorizeApiRequest
  def initialize(headers = {})
    @headers = headers
  end

  def call
    return nil unless decoded_auth_token && valid_token?
    
    {
      user: user,
      token_data: decoded_auth_token
    }
  end

  private

  attr_reader :headers

  def user
    @user ||= User.find(decoded_auth_token[:user_id]) if decoded_auth_token
  rescue ActiveRecord::RecordNotFound => e
    nil
  end

  def valid_token?
    return false unless decoded_auth_token
    
    jti = decoded_auth_token[:jti]
    user_id = decoded_auth_token[:user_id]
    issued_at = decoded_auth_token[:iat]
    
    # JTIがブラックリストに登録されているかチェック
    return false if TokenBlacklistService.blacklisted?(jti)
    
    # ユーザーが全ログアウトした後に発行されたトークンかチェック
    return false if TokenBlacklistService.user_logged_out_before?(user_id, issued_at)
    
    # トークンが期限切れでないかチェック
    return false if decoded_auth_token[:exp] < Time.current.to_i
    
    true
  end

  def decoded_auth_token
    @decoded_auth_token ||= JwtService.decode(token)
  end

  def token
    @token ||= http_auth_header
  end

  def http_auth_header
    if headers['Authorization'].present?
      return headers['Authorization'].split(' ').last
    end
    nil
  end
end
