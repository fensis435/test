# config/routes.rb
Rails.application.routes.draw do
  # 認証プロキシ用のエンドポイント
  namespace :auth do
    get 'verify', to: 'proxy#verify'
    get 'k8s_token', to: 'proxy#k8s_token'
  end
  
  # Grafanaへのプロキシ（オプション）
  get '/grafana', to: 'dashboards#grafana_redirect'
  
  # Kubernetes Dashboardへのプロキシ
  get '/k8s-dashboard', to: 'dashboards#k8s_dashboard'
  
  # 既存の認証ルート
  post '/login', to: 'sessions#create'
  delete '/logout', to: 'sessions#destroy'
  
  # ... その他のルート
end
