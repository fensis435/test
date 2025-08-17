class MaintenanceController < Api::V1::AuthenticatedController
  before_action :ensure_owner_or_admin, only: [:index, :cleanup_orphaned, :force_deploy, :force_undeply]
  before_action :initialize_maintenance_service

  def index
    @user_apps = @maintenance_service.list_all_user_apps
    @cluster_resources = @maintenance_service.get_cluster_resources
  end

  def cleanup_orphaned
    begin
      orphaned = @maintenance_service.cleanup_orphaned_resources
      flash[:notice] = "#{orphaned.length}個の孤立したリソースを削除しました"
    rescue K8s::BaseService::K8sError => e
      flash[:error] = "クリーンアップに失敗しました: #{e.message}"
    end
    
    redirect_to admin_maintenance_path
  end

  def force_deploy
    begin
      user_id = params[:user_id]
      @maintenance_service.force_deploy_user_app(user_id)
      flash[:notice] = "ユーザー#{user_id}のアプリを強制デプロイしました"
    rescue K8s::BaseService::K8sError => e
      flash[:error] = "強制デプロイに失敗しました: #{e.message}"
    end
    
    redirect_to admin_maintenance_path
  end

  def force_undeploy
    begin
      user_id = params[:user_id]
      @maintenance_service.force_undeploy_user_app(user_id)
      flash[:notice] = "ユーザー#{user_id}のアプリを強制アンデプロイしました"
    rescue K8s::BaseService::K8sError => e
      flash[:error] = "強制アンデプロイに失敗しました: #{e.message}"
    end
    
    redirect_to admin_maintenance_path
  end

  private

  def initialize_maintenance_service
    @maintenance_service = K8s::MaintenanceService.new
  end

  def authenticate_admin!
    redirect_to root_path unless current_user&.admin?
  end
end

