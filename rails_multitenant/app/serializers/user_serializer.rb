module Serializers
  class UserSerializer
    def initialize(user)
      @user = user
    end

    def as_json
      {
        id: @user.id,
        cognito_sub: @user.cognito_sub,
        email: @user.email,
        display_name: @user.display_name,
        role: @user.role,
        active: @user.active?,
        created_at: @user.created_at&.iso8601,
        updated_at: @user.updated_at&.iso8601
      }
    end
  end
end
