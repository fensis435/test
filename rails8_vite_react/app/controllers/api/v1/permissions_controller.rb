class PermissionsController < Api::V1::AuthenticatedController

  def index
    # admin:read 権限が必要
    @permissions = Permission.all.order(:name)
    render json: {
      permissions: @permissions.map do |permission|
        {
          id: permission.id,
          name: permission.name,
          role: permission.role,
          access_level: permission.access_level,
          description: permission.description,
          users_count: permission.users.count
        }
      end
    }
  end

  def create
    # admin:write 権限が必要
    @permission = Permission.new(permission_params)
    
    if @permission.save
      render json: @permission, status: :created
    else
      render json: { errors: @permission.errors }, status: :unprocessable_entity
    end
  end

  def update
    # admin:write 権限が必要
    @permission = Permission.find(params[:id])
    
    if @permission.update(permission_params)
      render json: @permission
    else
      render json: { errors: @permission.errors }, status: :unprocessable_entity
    end
  end

  def destroy
    # admin:write 権限が必要
    @permission = Permission.find(params[:id])
    @permission.destroy
    head :no_content
  end

  private

  def permission_params
    params.require(:permission).permit(:name, :description)
  end

end
