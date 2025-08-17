class UserAppsController < Api::V1::AuthenticatedController
  before_action :ensure_owner_or_admin, only: [:show, :deploy, :undeply, :start, :stop, :restart, :logs ]
  before_action :initialize_user_app_service

  def show
    @status = @user_app_service.app_status
    @app_url = current_user.app_url
    @logs = @user_app_service.app_logs(lines: 50) if @status == 'running'
  end

  def deploy
    begin
      result = @user_app_service.deploy_user_app
      flash[:notice] = "アプリをデプロイしました: #{result[:url]}"
    rescue K8s::BaseService::K8sError => e
      flash[:error] = "デプロイに失敗しました: #{e.message}"
    end
    
    redirect_to user_app_path
  end

  def undeploy
    begin
      @user_app_service.undeploy_user_app
      flash[:notice] = "アプリをアンデプロイしました"
    rescue K8s::BaseService::K8sError => e
      flash[:error] = "アンデプロイに失敗しました: #{e.message}"
    end
    
    redirect_to user_app_path
  end

  def start
    begin
      @user_app_service.start_user_app
      flash[:notice] = "アプリを起動しました"
    rescue K8s::BaseService::K8sError => e
      flash[:error] = "起動に失敗しました: #{e.message}"
    end
    
    redirect_to user_app_path
  end

  def stop
    begin
      @user_app_service.stop_user_app
      flash[:notice] = "アプリを停止しました"
    rescue K8s::BaseService::K8sError => e
      flash[:error] = "停止に失敗しました: #{e.message}"
    end
    
    redirect_to user_app_path
  end

  def restart
    begin
      @user_app_service.restart_user_app
      flash[:notice] = "アプリを再起動しました"
    rescue K8s::BaseService::K8sError => e
      flash[:error] = "再起動に失敗しました: #{e.message}"
    end
    
    redirect_to user_app_path
  end

  def logs
    @logs = @user_app_service.app_logs(lines: params[:lines]&.to_i || 100)
    render json: { logs: @logs }
  end

  private

  def initialize_user_app_service
    @user_app_service = K8s::UserAppService.new(current_user)
  end
end
