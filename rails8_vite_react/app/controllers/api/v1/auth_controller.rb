class Api::V1::AuthController < Api::V1::PublicController  
  skip_before_action :verify_authenticity_token  # API用ならCSRF無効化

  def login
    identifier = params[:user][:email] # email欄にemailまたはnameが入る
    password = params[:user][:password]
    user = User.find_by('email = ? OR name = ?', identifier, identifier)
    if user&.authenticate(params[:password])
      token = user.generate_jwt
      render json: { user: user_response(user), token: token }
    else
      render json: { error: 'Invalid credentials' }, status: :unauthorized
    end
  end

  def me
    render json: { user: user_response(current_user) }
  end
  
  private
  
  def user_params
    params.require(:user).permit(:email, :password, :name)
  end
  
  def user_response(user)
    {
      id: user.id,
      email: user.email,
      name: user.name
    }
  end
end
