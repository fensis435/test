class Api::V1::UsersController < Api::V1::AuthenticatedController
  skip_before_action :authenticate_user, only: [:create]  # 明示的にスキップ
  before_action :set_user, only: [:show, :update, :destroy, :me]
  before_action :authorize_user, only: [:update, :destroy, :me]

  def create
    user = User.new(user_params)
    if user.save
      token = user.generate_jwt
      render json: {
        success: true,
        user: user_response(user),
        token: token
      }, status: :created
    else
      render json: { 
        success: false,
        errors: user.errors.full_messages 
      }, status: :unprocessable_entity
    end
  end

  def show
    render json: { 
      success: true,
      user: user_response(@user) 
    }
  end

  def update
    if @user.update(update_user_params)
      render json: { 
        success: true,
        user: user_response(@user),
        message: 'User updated successfully'
      }
    else
      render json: { 
        success: false,
        errors: @user.errors.full_messages 
      }, status: :unprocessable_entity
    end
  end

  def destroy
    @user.destroy!
    render json: { 
      success: true,
      message: 'User deleted successfully' 
    }
  end

  def me
    render json: { 
      success: true,
      user: user_response(current_user, include_private: true) 
    }
  end

  private

  def set_user
    @user = User.find(params[:id])
  end

  def authorize_user
    unless current_user == @user || current_user&.admin?
      render json: { error: 'Unauthorized' }, status: :forbidden
    end
  end

  def user_params
    params.require(:user).permit(:email, :password, :password_confirmation, :name)
  end

  def update_user_params
    params.require(:user).permit(:email, :name, :bio, :avatar, :phone, :date_of_birth)
  end

  def user_response(user, include_private: false)
    response = {
      id: user.id,
      name: user.name,
      email: user.email,
      created_at: user.created_at,
      updated_at: user.updated_at
    }

    if include_private && (current_user == user || current_user&.admin?)
      response.merge!(
        phone: user.phone,
        date_of_birth: user.date_of_birth,
        email_verified: user.email_verified?,
        last_sign_in_at: user.last_sign_in_at
      )
    end

    response
  end
end
