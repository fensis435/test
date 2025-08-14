class Api::V1::UsersController < Api::V1::AuthenticatedController
  before_action :set_user, only: [:show, :update, :destroy]
  before_action :ensure_admin, only: [:index, :destroy]
  before_action :ensure_owner_or_admin, only: [:show, :update]

  # GET /api/v1/users
  # 管理者のみアクセス可能
  def index
    @users = User.select(:id, :name, :email, :created_at, :updated_at)
                 .order(:created_at)
                 .page(params[:page])
                 .per(params[:per_page] || 20)

    render json: {
      users: @users,
      meta: {
        current_page: @users.current_page,
        per_page: @users.limit_value,
        total_pages: @users.total_pages,
        total_count: @users.total_count
      }
    }, status: :ok
  end

  # GET /api/v1/users/:id
  # 本人または管理者のみアクセス可能
  def show
    render json: {
      user: {
        id: @user.id,
        name: @user.name,
        email: @user.email,
        created_at: @user.created_at,
        updated_at: @user.updated_at,
        active_sessions_count: @user.active_sessions_count
      }
    }, status: :ok
  end

  # GET /api/v1/users/me
  # 現在のユーザー情報を取得
  def me
    render json: {
      user: {
        id: current_user.id,
        name: current_user.name,
        email: current_user.email,
        created_at: current_user.created_at,
        updated_at: current_user.updated_at,
        active_sessions_count: current_user.active_sessions_count
      }
    }, status: :ok
  end

  # POST /api/v1/users
  # 新規ユーザー登録（パブリック、または管理者のみ）
  def create
    # 管理者でない場合は新規登録を許可するかチェック
    unless current_user_admin? || registration_allowed?
      render json: { error: 'Registration is not allowed' }, status: :forbidden
      return
    end

    @user = User.new(user_params)
    
    if @user.save
      # 新規登録の場合は自動ログイン用のトークンを生成
      if !current_user_admin?
        access_token = JwtService.encode(user_id: @user.id)
        refresh_token = JwtService.encode_refresh_token(user_id: @user.id)
        
        # セッション情報を保存
        access_decoded = JwtService.decode(access_token)
        refresh_decoded = JwtService.decode(refresh_token)
        device_info = extract_device_info
        
        @user.create_session(access_decoded[:jti], 'access', access_decoded[:exp], device_info)
        @user.create_session(refresh_decoded[:jti], 'refresh', refresh_decoded[:exp], device_info)

        render json: {
          message: 'User created successfully',
          user: {
            id: @user.id,
            name: @user.name,
            email: @user.email
          },
          access_token: access_token,
          refresh_token: refresh_token
        }, status: :created
      else
        render json: {
          message: 'User created successfully',
          user: {
            id: @user.id,
            name: @user.name,
            email: @user.email,
            created_at: @user.created_at
          }
        }, status: :created
      end
    else
      render json: {
        error: 'User creation failed',
        errors: @user.errors.full_messages
      }, status: :unprocessable_entity
    end
  end

  # PUT/PATCH /api/v1/users/:id
  # 本人または管理者のみ更新可能
  def update
    if @user.update(user_update_params)
      render json: {
        message: 'User updated successfully',
        user: {
          id: @user.id,
          name: @user.name,
          email: @user.email,
          updated_at: @user.updated_at
        }
      }, status: :ok
    else
      render json: {
        error: 'User update failed',
        errors: @user.errors.full_messages
      }, status: :unprocessable_entity
    end
  end

  # DELETE /api/v1/users/:id
  # 管理者のみ削除可能（自分自身は削除不可）
  def destroy
    if @user.id == current_user.id
      render json: { error: 'Cannot delete your own account' }, status: :forbidden
      return
    end

    if @user.destroy
      # ユーザーのすべてのセッションを無効化
      TokenBlacklistService.blacklist_user_all_tokens(@user.id)
      
      render json: { message: 'User deleted successfully' }, status: :ok
    else
      render json: {
        error: 'User deletion failed',
        errors: @user.errors.full_messages
      }, status: :unprocessable_entity
    end
  end

  # PUT /api/v1/users/:id/change_password
  # 本人または管理者のみパスワード変更可能
  def change_password
    @user = User.find(params[:id])
    ensure_owner_or_admin

    # 本人の場合は現在のパスワードが必要
    if @user.id == current_user.id
      unless @user.authenticate(params[:current_password])
        render json: { error: 'Current password is incorrect' }, status: :unauthorized
        return
      end
    end

    if @user.update(password: params[:new_password], password_confirmation: params[:password_confirmation])
      # パスワード変更後は他のセッションを無効化
      TokenBlacklistService.blacklist_user_all_tokens(@user.id)
      
      render json: { message: 'Password changed successfully' }, status: :ok
    else
      render json: {
        error: 'Password change failed',
        errors: @user.errors.full_messages
      }, status: :unprocessable_entity
    end
  end

  # GET /api/v1/users/search
  # 管理者のみ：ユーザー検索
  def search
    ensure_admin
    
    query = params[:q]
    if query.blank?
      render json: { error: 'Search query is required' }, status: :bad_request
      return
    end

    @users = User.where(
      "name ILIKE :query OR email ILIKE :query", 
      query: "%#{query}%"
    ).select(:id, :name, :email, :created_at)
     .limit(20)

    render json: { users: @users }, status: :ok
  end

  # GET /api/v1/users/:id/sessions
  # 本人または管理者のみ：ユーザーのセッション一覧
  def sessions
    @user = User.find(params[:id])
    ensure_owner_or_admin

    sessions = @user.user_sessions.active.refresh_tokens
                   .select(:id, :device_info, :created_at, :last_used_at)
                   .order(created_at: :desc)

    render json: {
      sessions: sessions,
      total_count: sessions.count
    }, status: :ok
  end

  private

  def set_user
    @user = User.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'User not found' }, status: :not_found
  end

  def user_params
    params.require(:user).permit(:name, :email, :password, :password_confirmation)
  end

  def user_update_params
    # パスワードは別のエンドポイントで変更
    params.require(:user).permit(:name, :email)
  end

  def ensure_admin
    unless current_user_admin?
      render json: { error: 'Admin access required' }, status: :forbidden
    end
  end

  def ensure_owner_or_admin
    unless @user.id == current_user[:user].id || current_user_admin?
      render json: { error: 'Access denied' }, status: :forbidden
    end
  end

  def current_user_admin?
    # 管理者フラグがある場合はそれを使用、なければ仮実装
    current_user[:user].respond_to?(:admin?) ? current_user[:user].admin? : false
  end

  def registration_allowed?
    # 新規登録の許可設定（環境変数や設定から取得）
    Rails.application.config.allow_registration != false
  end

  def extract_device_info
    user_agent = request.headers['User-Agent']
    ip_address = request.remote_ip
    
    {
      user_agent: user_agent&.truncate(200),
      ip_address: ip_address,
      created_at: Time.current
    }.to_json
  end

end
