class Api::V1::AuthController < Api::V1::PublicController  
  skip_before_action :verify_authenticity_token  # API用ならCSRF無効化
  skip_before_action :authenticate_request, only: [:login, :refresh]

  def login
    #logger.info "params=#{params}"
    identifier = params[:email] # email欄にemailまたはnameが入る
    @user = User.find_by('email = ? OR name = ?', identifier, identifier)
    if @user&.authenticate(params[:password])
      device_info = extract_device_info
      
      access_payload = { user_id: @user.id }
      refresh_payload = { user_id: @user.id }
      
      access_token = JwtService.encode(access_payload)
      refresh_token = JwtService.encode_refresh_token(refresh_payload)
      
      # デコードしてJTIを取得
      access_decoded = JwtService.decode(access_token)
      refresh_decoded = JwtService.decode(refresh_token)
      
      # セッション情報をDBに保存
      @user.create_session(access_decoded[:jti], 'access', access_decoded[:exp], device_info)
      @user.create_session(refresh_decoded[:jti], 'refresh', refresh_decoded[:exp], device_info)
      
      render json: { 
        access_token: access_token,
        refresh_token: refresh_token,
        user: {
          id: @user.id,
          name: @user.name,
          email: @user.email,
          role: @user.role
        }
      }, status: :ok
    else
      render json: { error: 'Invalid credentials' }, status: :unauthorized
    end
  end

  def refresh
    refresh_token = params[:refresh_token]
    decoded_token = JwtService.decode(refresh_token)
    
    if decoded_token && 
       decoded_token[:type] == 'refresh' && 
       !TokenBlacklistService.blacklisted?(decoded_token[:jti])
      
      user = User.find(decoded_token[:user_id])
      device_info = extract_device_info
      
      # 古いrefresh tokenをブラックリストに追加
      TokenBlacklistService.blacklist_token(
        decoded_token[:jti], 
        decoded_token[:exp], 
        user.id
      )
      
      # 新しいトークンを発行
      access_payload = { user_id: user.id }
      refresh_payload = { user_id: user.id }
      
      new_access_token = JwtService.encode(access_payload)
      new_refresh_token = JwtService.encode_refresh_token(refresh_payload)
      
      # 新しいセッション情報をDBに保存
      access_decoded = JwtService.decode(new_access_token)
      refresh_decoded = JwtService.decode(new_refresh_token)
      
      user.create_session(access_decoded[:jti], 'access', access_decoded[:exp], device_info)
      user.create_session(refresh_decoded[:jti], 'refresh', refresh_decoded[:exp], device_info)
      
      render json: { 
        access_token: new_access_token,
        refresh_token: new_refresh_token 
      }, status: :ok
    else
      render json: { error: 'Invalid refresh token' }, status: :unauthorized
    end
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Invalid refresh token' }, status: :unauthorized
  end

  def logout
    if current_token
      jti = current_token[:jti]
      exp = current_token[:exp]

      # セッションを削除
      current_user.user_sessions.where(jti: jti).destroy_all
      
      # アクセストークンをブラックリストに追加
      TokenBlacklistService.blacklist_token(jti, exp, current_user.id)
      
      # リフレッシュトークンもブラックリストに追加（送信された場合）
      if params[:refresh_token].present?
        refresh_decoded = JwtService.decode(params[:refresh_token])
        if refresh_decoded && refresh_decoded[:jti]
          TokenBlacklistService.blacklist_token(
            refresh_decoded[:jti], 
            refresh_decoded[:exp], 
            current_user.id
          )
        end
      end
      
      render json: { message: 'Successfully logged out' }, status: :ok
    else
      render json: { error: 'Invalid token' }, status: :unauthorized
    end
  end

  def logout_all
    # 特定ユーザーのすべてのセッションを無効化
    TokenBlacklistService.blacklist_user_all_tokens(current_user.id)
    current_user.user_sessions.destroy_all
    render json: { message: 'Successfully logged out from all devices' }, status: :ok
  end

  def sessions
    # ユーザーのアクティブなセッション一覧
    sessions = current_user.user_sessions.active.refresh_tokens
                          .select(:id, :device_info, :created_at)
                          .order(created_at: :desc)
                          .to_a
    
    render json: { 
      sessions: sessions,
      total_count: sessions.count 
    }, status: :ok
  end

  def me
    render json: { user: user_response(current_user) }
  end

  private

  def extract_device_info
    user_agent = request.headers['User-Agent']
    ip_address = request.remote_ip
    
    {
      user_agent: user_agent&.truncate(200),
      ip_address: ip_address,
      created_at: Time.current
    }.to_json
  end

  def user_params
    params.require(:user).permit(:email, :password, :name)
  end
  
  def user_response(user)
    {
      id: user.id,
      email: user.email,
      name: user.name,
      role: user.role
    }
  end

end
