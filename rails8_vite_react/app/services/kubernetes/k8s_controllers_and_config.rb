# config/initializers/k8s.rb
# Kubernetes設定の初期化
Rails.application.configure do
  # kubeclient gemの設定確認
  config.after_initialize do
    begin
      # Test connection to Kubernetes API
      test_client = Kubeclient::Client.new(
        Rails.application.config.k8s_api_endpoint,
        'v1',
        auth_options: k8s_auth_options,
        ssl_options: k8s_ssl_options
      )
      
      version = test_client.api_valid?
      Rails.logger.info "Kubernetes API connection successful"
      
      # Test helm availability
      helm_version = `helm version --short 2>/dev/null`
      Rails.logger.info "helm: #{helm_version.strip}" if $?.success?
      
      # 設定値の検証
      required_configs = %w[helm_chart_path app_base_domain k8s_api_endpoint]
      missing_configs = required_configs.select { |config| Rails.application.config.send(config).blank? }
      
      if missing_configs.any?
        Rails.logger.warn "Missing required Kubernetes configurations: #{missing_configs.join(', ')}"
      end
      
    rescue => e
      Rails.logger.error "Failed to initialize Kubernetes configuration: #{e.message}"
    end
  end

  private

  def k8s_auth_options
    if Rails.application.config.k8s_token.present?
      { bearer_token: Rails.application.config.k8s_token }
    elsif Rails.application.config.k8s_username.present?
      {
        username: Rails.application.config.k8s_username,
        password: Rails.application.config.k8s_password
      }
    else
      {} # Use kubeconfig default
    end
  end

  def k8s_ssl_options
    if Rails.application.config.k8s_verify_ssl == false
      { verify_ssl: OpenSSL::SSL::VERIFY_NONE }
    else
      {}
    end
  end
end# app/controllers/user_apps_controller.rb
class UserAppsController < ApplicationController
  before_action :authenticate_user!
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

# app/controllers/admin/maintenance_controller.rb
class Admin::MaintenanceController < ApplicationController
  before_action :authenticate_admin!
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

# app/models/concerns/user_app_lifecycle.rb
module UserAppLifecycle
  extend ActiveSupport::Concern

  included do
    after_create :schedule_app_deployment
    before_destroy :cleanup_user_resources
  end

  def user_app_service
    @user_app_service ||= K8s::UserAppService.new(self)
  end

  def deploy_app_if_needed
    return if k8s_namespace.present?
    
    UserAppDeployJob.perform_later(id)
  end

  def start_app_on_login
    return unless should_start_app?
    
    UserAppStartJob.perform_later(id)
    update!(last_login_at: Time.current)
  end

  def stop_app_on_timeout
    return unless should_stop_app?
    
    UserAppStopJob.perform_later(id)
  end

  def app_running?
    app_status == 'running'
  end

  def app_stopped?
    app_status == 'stopped'
  end

  private

  def schedule_app_deployment
    UserAppDeployJob.perform_later(id) if auto_deploy_enabled?
  end

  def cleanup_user_resources
    UserAppCleanupJob.perform_later(id)
  end

  def should_start_app?
    k8s_namespace.present? && !app_running?
  end

  def should_stop_app?
    app_running? && session_expired?
  end

  def session_expired?
    return false unless last_login_at.present?
    
    timeout_minutes = Rails.application.config.session_timeout_minutes || 30
    last_login_at < timeout_minutes.minutes.ago
  end

  def auto_deploy_enabled?
    Rails.application.config.auto_deploy_user_apps || false
  end
end

# app/jobs/user_app_deploy_job.rb
class UserAppDeployJob < ApplicationJob
  queue_as :k8s_operations
  
  retry_on K8s::BaseService::K8sError, wait: 30.seconds, attempts: 3

  def perform(user_id)
    user = User.find(user_id)
    service = K8s::UserAppService.new(user)
    
    service.deploy_user_app
    
    Rails.logger.info "Successfully deployed app for user #{user_id}"
  rescue => e
    Rails.logger.error "Failed to deploy app for user #{user_id}: #{e.message}"
    raise
  end
end

# app/jobs/user_app_start_job.rb
class UserAppStartJob < ApplicationJob
  queue_as :k8s_operations
  
  retry_on K8s::BaseService::K8sError, wait: 10.seconds, attempts: 2

  def perform(user_id)
    user = User.find(user_id)
    service = K8s::UserAppService.new(user)
    
    service.start_user_app
    
    Rails.logger.info "Successfully started app for user #{user_id}"
  rescue => e
    Rails.logger.error "Failed to start app for user #{user_id}: #{e.message}"
    raise
  end
end

# app/jobs/user_app_stop_job.rb
class UserAppStopJob < ApplicationJob
  queue_as :k8s_operations
  
  retry_on K8s::BaseService::K8sError, wait: 10.seconds, attempts: 2

  def perform(user_id)
    user = User.find(user_id)
    service = K8s::UserAppService.new(user)
    
    service.stop_user_app
    
    Rails.logger.info "Successfully stopped app for user #{user_id}"
  rescue => e
    Rails.logger.error "Failed to stop app for user #{user_id}: #{e.message}"
    raise
  end
end

# app/jobs/user_app_cleanup_job.rb
class UserAppCleanupJob < ApplicationJob
  queue_as :k8s_operations
  
  def perform(user_id)
    # Find user record or create a temporary one for cleanup
    user = User.find_by(id: user_id) || 
           User.new(id: user_id, k8s_namespace: find_user_namespace(user_id))
    
    service = K8s::UserAppService.new(user)
    service.undeploy_user_app
    
    Rails.logger.info "Successfully cleaned up resources for user #{user_id}"
  rescue => e
    Rails.logger.error "Failed to cleanup resources for user #{user_id}: #{e.message}"
  end

  private

  def find_user_namespace(user_id)
    service = K8s::NamespaceService.new
    namespaces = service.list_user_namespaces(user_id)
    namespaces.first
  end
end

# app/jobs/session_timeout_monitor_job.rb
class SessionTimeoutMonitorJob < ApplicationJob
  queue_as :default

  def perform
    timeout_minutes = Rails.application.config.session_timeout_minutes || 30
    expired_users = User.joins(:user_sessions)
                       .where(app_status: 'running')
                       .where('user_sessions.updated_at < ?', timeout_minutes.minutes.ago)
                       .distinct

    expired_users.find_each do |user|
      UserAppStopJob.perform_later(user.id)
    end

    Rails.logger.info "Scheduled stop jobs for #{expired_users.count} expired user sessions"
  end
end

# config/application.rb (追加設定)
class Application < Rails::Application
  # Kubernetes configuration
  config.helm_chart_path = ENV['HELM_CHART_PATH'] || './helm-charts/user-app'
  config.helm_chart_name = ENV['HELM_CHART_NAME'] || 'user-app'
  config.helm_values_file = ENV['HELM_VALUES_FILE'] || './helm-charts/user-app/values.yaml'
  config.app_image_tag = ENV['APP_IMAGE_TAG'] || 'latest'
  config.app_base_domain = ENV['APP_BASE_DOMAIN'] || 'app.example.com'
  
  # Kubernetes API configuration
  config.k8s_api_endpoint = ENV['K8S_API_ENDPOINT'] || 'https://kubernetes.default.svc'
  config.k8s_token = ENV['K8S_TOKEN'] # Service account token
  config.k8s_username = ENV['K8S_USERNAME']
  config.k8s_password = ENV['K8S_PASSWORD']
  config.k8s_verify_ssl = ENV['K8S_VERIFY_SSL'] != 'false'
  
  # Session and lifecycle configuration
  config.session_timeout_minutes = ENV['SESSION_TIMEOUT_MINUTES']&.to_i || 30
  config.auto_deploy_user_apps = ENV['AUTO_DEPLOY_USER_APPS'] == 'true'
  
  # Job queues
  config.active_job.queue_adapter = :sidekiq
end

# config/routes.rb (追加ルート)
Rails.application.routes.draw do
  # User app management
  resource :user_app, only: [:show] do
    member do
      post :deploy
      delete :undeploy
      post :start
      post :stop
      post :restart
      get :logs
    end
  end

  # Admin maintenance
  namespace :admin do
    resource :maintenance, only: [:index] do
      member do
        post :cleanup_orphaned
        post :force_deploy
        post :force_undeploy
      end
    end
  end
end

# config/schedule.rb (whenever gem用)
every 5.minutes do
  runner "SessionTimeoutMonitorJob.perform_later"
end

every 1.day, at: '3:00 am' do
  runner "K8s::MaintenanceService.new.cleanup_orphaned_resources"
end

# db/migrate/xxxx_add_k8s_fields_to_users.rb
class AddK8sFieldsToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :k8s_namespace, :string
    add_column :users, :k8s_release_name, :string
    add_column :users, :app_url, :string
    add_column :users, :app_status, :string, default: 'not_deployed'
    add_column :users, :last_login_at, :timestamp
    
    add_index :users, :k8s_namespace
    add_index :users, :app_status
    add_index :users, :last_login_at
  end
end

# app/models/user.rb (追加部分)
class User < ApplicationRecord
  include UserAppLifecycle
  
  # ... 既存のコード ...
  
  enum app_status: {
    not_deployed: 'not_deployed',
    running: 'running',
    stopped: 'stopped',
    starting: 'starting',
    error: 'error'
  }

  scope :with_running_apps, -> { where(app_status: 'running') }
  scope :with_deployed_apps, -> { where.not(app_status: 'not_deployed') }
  scope :session_expired, ->(timeout_minutes = 30) {
    where('last_login_at < ?', timeout_minutes.minutes.ago)
  }
end

# app/controllers/application_controller.rb (セッション管理追加)
class ApplicationController < ActionController::Base
  before_action :update_user_login_time
  after_action :schedule_app_lifecycle

  private

  def update_user_login_time
    return unless user_signed_in?
    
    current_user.update_column(:last_login_at, Time.current)
  end

  def schedule_app_lifecycle
    return unless user_signed_in?
    
    # ログイン時にアプリ起動をスケジュール
    if session[:just_signed_in]
      current_user.start_app_on_login
      session.delete(:just_signed_in)
    end
  end
end

# app/controllers/sessions_controller.rb (Deviseをオーバーライド)
class SessionsController < Devise::SessionsController
  def create
    super do |user|
      session[:just_signed_in] = true if user.persisted?
    end
  end

  def destroy
    # セッション終了時にアプリ停止をスケジュール
    current_user&.stop_app_on_timeout if current_user
    super
  end
end

# app/views/user_apps/show.html.erb
<div class="user-app-dashboard">
  <h1>マイアプリ管理</h1>

  <div class="app-status-card">
    <h2>ステータス</h2>
    <div class="status-indicator status-<%= @status %>">
      <%= @status.humanize %>
    </div>
    
    <% if @app_url.present? %>
      <p>
        <strong>URL:</strong> 
        <a href="<%= @app_url %>" target="_blank"><%= @app_url %></a>
      </p>
    <% end %>
  </div>

  <div class="app-controls">
    <h2>操作</h2>
    
    <% case @status %>
    <% when 'not_deployed' %>
      <%= link_to 'アプリをデプロイ', deploy_user_app_path, 
                  method: :post, class: 'btn btn-primary',
                  confirm: 'アプリをデプロイしますか？' %>
    
    <% when 'stopped' %>
      <%= link_to 'アプリを起動', start_user_app_path, 
                  method: :post, class: 'btn btn-success' %>
      <%= link_to 'アプリを削除', undeploy_user_app_path, 
                  method: :delete, class: 'btn btn-danger',
                  confirm: 'アプリを完全に削除しますか？' %>
    
    <% when 'running' %>
      <%= link_to 'アプリを停止', stop_user_app_path, 
                  method: :post, class: 'btn btn-warning' %>
      <%= link_to 'アプリを再起動', restart_user_app_path, 
                  method: :post, class: 'btn btn-info' %>
      <%= link_to 'アプリを削除', undeploy_user_app_path, 
                  method: :delete, class: 'btn btn-danger',
                  confirm: 'アプリを完全に削除しますか？' %>
    
    <% when 'starting' %>
      <p>アプリを起動中です...</p>
      <div class="spinner"></div>
    
    <% when 'error' %>
      <p class="error">エラーが発生しています</p>
      <%= link_to 'アプリを再起動', restart_user_app_path, 
                  method: :post, class: 'btn btn-warning' %>
      <%= link_to 'アプリを削除', undeploy_user_app_path, 
                  method: :delete, class: 'btn btn-danger',
                  confirm: 'アプリを完全に削除しますか？' %>
    <% end %>
  </div>

  <% if @status == 'running' && @logs.present? %>
    <div class="app-logs">
      <h2>最新ログ</h2>
      <div class="log-container">
        <% @logs.each do |log_line| %>
          <div class="log-line"><%= log_line %></div>
        <% end %>
      </div>
      <button id="refresh-logs" class="btn btn-sm btn-secondary">ログを更新</button>
    </div>
  <% end %>
</div>

<script>
document.addEventListener('DOMContentLoaded', function() {
  // Auto-refresh status every 30 seconds
  setInterval(function() {
    location.reload();
  }, 30000);

  // Refresh logs button
  const refreshBtn = document.getElementById('refresh-logs');
  if (refreshBtn) {
    refreshBtn.addEventListener('click', function() {
      fetch('<%= logs_user_app_path %>')
        .then(response => response.json())
        .then(data => {
          const logContainer = document.querySelector('.log-container');
          logContainer.innerHTML = data.logs.map(line => 
            `<div class="log-line">${line}</div>`
          ).join('');
        });
    });
  }
});
</script>

# app/views/admin/maintenance/index.html.erb
<div class="maintenance-dashboard">
  <h1>システム保守</h1>

  <div class="cluster-overview">
    <h2>クラスター概要</h2>
    <div class="stats-grid">
      <div class="stat-card">
        <h3>ノード数</h3>
        <p><%= @cluster_resources[:nodes].length %></p>
      </div>
      <div class="stat-card">
        <h3>総Pod数</h3>
        <p><%= @cluster_resources[:pods] %></p>
      </div>
      <div class="stat-card">
        <h3>ユーザーアプリ数</h3>
        <p><%= @cluster_resources[:user_apps] %></p>
      </div>
    </div>
  </div>

  <div class="maintenance-actions">
    <h2>保守操作</h2>
    <%= link_to '孤立リソースのクリーンアップ', cleanup_orphaned_admin_maintenance_path,
                method: :post, class: 'btn btn-warning',
                confirm: '孤立したリソースを削除しますか？' %>
  </div>

  <div class="user-apps-table">
    <h2>全ユーザーアプリ</h2>
    <table class="table">
      <thead>
        <tr>
          <th>ユーザーID</th>
          <th>Namespace</th>
          <th>Release</th>
          <th>ステータス</th>
          <th>更新日時</th>
          <th>操作</th>
        </tr>
      </thead>
      <tbody>
        <% @user_apps.each do |app| %>
          <tr>
            <td><%= app[:user_id] %></td>
            <td><%= app[:namespace] %></td>
            <td><%= app[:release_name] %></td>
            <td><span class="status-badge status-<%= app[:status] %>"><%= app[:status] %></span></td>
            <td><%= app[:updated] %></td>
            <td>
              <%= link_to '強制デプロイ', force_deploy_admin_maintenance_path,
                          method: :post, params: { user_id: app[:user_id] },
                          class: 'btn btn-sm btn-primary' %>
              <%= link_to '強制削除', force_undeploy_admin_maintenance_path,
                          method: :post, params: { user_id: app[:user_id] },
                          class: 'btn btn-sm btn-danger',
                          confirm: '本当に削除しますか？' %>
            </td>
          </tr>
        <% end %>
      </tbody>
    </table>
  </div>
</div>

# app/assets/stylesheets/user_apps.scss
.user-app-dashboard {
  max-width: 800px;
  margin: 0 auto;
  padding: 20px;

  .app-status-card {
    background: #f8f9fa;
    border-radius: 8px;
    padding: 20px;
    margin-bottom: 20px;

    .status-indicator {
      display: inline-block;
      padding: 8px 16px;
      border-radius: 20px;
      font-weight: bold;
      margin: 10px 0;

      &.status-running { background: #28a745; color: white; }
      &.status-stopped { background: #6c757d; color: white; }
      &.status-starting { background: #ffc107; color: black; }
      &.status-not_deployed { background: #e9ecef; color: #495057; }
      &.status-error { background: #dc3545; color: white; }
    }
  }

  .app-controls {
    margin-bottom: 20px;

    .btn {
      margin-right: 10px;
      margin-bottom: 10px;
    }
  }

  .app-logs {
    .log-container {
      background: #000;
      color: #0f0;
      font-family: monospace;
      padding: 10px;
      height: 300px;
      overflow-y: scroll;
      border-radius: 4px;
      margin-bottom: 10px;

      .log-line {
        margin-bottom: 2px;
      }
    }
  }

  .spinner {
    border: 4px solid #f3f3f3;
    border-top: 4px solid #3498db;
    border-radius: 50%;
    width: 30px;
    height: 30px;
    animation: spin 2s linear infinite;
    display: inline-block;
  }
}

@keyframes spin {
  0% { transform: rotate(0deg); }
  100% { transform: rotate(360deg); }
}

.maintenance-dashboard {
  padding: 20px;

  .stats-grid {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
    gap: 20px;
    margin-bottom: 30px;

    .stat-card {
      background: #f8f9fa;
      padding: 20px;
      border-radius: 8px;
      text-align: center;

      h3 { margin: 0 0 10px 0; color: #6c757d; }
      p { font-size: 2em; font-weight: bold; margin: 0; }
    }
  }

  .status-badge {
    padding: 4px 8px;
    border-radius: 12px;
    font-size: 12px;
    font-weight: bold;

    &.status-deployed { background: #28a745; color: white; }
    &.status-uninstalled { background: #6c757d; color: white; }
    &.status-failed { background: #dc3545; color: white; }
  }

  .table {
    width: 100%;
    border-collapse: collapse;

    th, td {
      padding: 12px;
      text-align: left;
      border-bottom: 1px solid #ddd;
    }

    th {
      background: #f8f9fa;
      font-weight: bold;
    }
  }
}

# config/initializers/k8s.rb
# Kubernetes設定の初期化
Rails.application.configure do
  # kubectlとhelmコマンドのパスを確認
  config.after_initialize do
    begin
      kubectl_version = `kubectl version --client --short 2>/dev/null`
      helm_version = `helm version --short 2>/dev/null`
      
      Rails.logger.info "Kubernetes tools detected:"
      Rails.logger.info "kubectl: #{kubectl_version.strip}" if $?.success?
      Rails.logger.info "helm: #{helm_version.strip}" if $?.success?
      
      # 設定値の検証
      required_configs = %w[helm_chart_path app_base_domain]
      missing_configs = required_configs.select { |config| Rails.application.config.send(config).blank? }
      
      if missing_configs.any?
        Rails.logger.warn "Missing required Kubernetes configurations: #{missing_configs.join(', ')}"
      end
      
    rescue => e
      Rails.logger.error "Failed to initialize Kubernetes configuration: #{e.message}"
    end
  end
end