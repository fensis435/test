# lib/grafana_role_sync.rb
# Grafanaのユーザー権限を動的に更新するためのスクリプト

require 'net/http'
require 'json'

class GrafanaRoleSync
  GRAFANA_API_URL = ENV['GRAFANA_API_URL'] || 'http://grafana.monitoring.svc.cluster.local:3000'
  GRAFANA_ADMIN_TOKEN = ENV['GRAFANA_ADMIN_TOKEN']
  
  ROLE_MAPPING = {
    'admin' => 'Admin',
    'editor' => 'Editor',
    'viewer' => 'Viewer'
  }.freeze
  
  def initialize
    @uri = URI(GRAFANA_API_URL)
  end
  
  # ユーザーのロールを同期
  def sync_user_role(user)
    grafana_user = find_or_create_grafana_user(user)
    return unless grafana_user
    
    desired_role = determine_role(user)
    update_user_role(grafana_user['id'], desired_role)
  end
  
  private
  
  def find_or_create_grafana_user(user)
    # Grafana APIでユーザーを検索
    response = api_request(:get, "/api/users/lookup?loginOrEmail=#{user.email}")
    
    if response.code == '200'
      JSON.parse(response.body)
    else
      # ユーザーが存在しない場合は自動作成される（auto_sign_up設定による）
      nil
    end
  end
  
  def determine_role(user)
    # Railsのユーザー権限からGrafanaのロールを決定
    if user.admin?
      'Admin'
    elsif user.has_role?(:editor)
      'Editor'
    else
      'Viewer'
    end
  end
  
  def update_user_role(user_id, role)
    # organizationのユーザーロールを更新
    org_id = 1 # デフォルト組織
    
    payload = {
      role: role
    }
    
    response = api_request(
      :patch,
      "/api/orgs/#{org_id}/users/#{user_id}",
      payload
    )
    
    response.code == '200'
  end
  
  def api_request(method, path, body = nil)
    uri = URI("#{GRAFANA_API_URL}#{path}")
    
    http = Net::HTTP.new(uri.host, uri.port)
    
    request = case method
              when :get
                Net::HTTP::Get.new(uri)
              when :post
                Net::HTTP::Post.new(uri)
              when :patch
                Net::HTTP::Patch.new(uri)
              end
    
    request['Authorization'] = "Bearer #{GRAFANA_ADMIN_TOKEN}"
    request['Content-Type'] = 'application/json'
    request.body = body.to_json if body
    
    http.request(request)
  end
end

# Sidekiqジョブとして実行する例
class SyncGrafanaRoleJob < ApplicationJob
  queue_as :default
  
  def perform(user_id)
    user = User.find(user_id)
    GrafanaRoleSync.new.sync_user_role(user)
  end
end
