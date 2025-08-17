# Kubernetes Control System for Rails 8.0 (kubeclient gem版)

Rails 8.0で`kubeclient` gemを使用してユーザー毎に専用のKubernetesアプリを管理するシステムです。

## 機能概要

1. **ユーザー毎の専用アプリデプロイ**: HelmとKubernetes Ruby APIを使用して、各ユーザーに独立したnamespaceでアプリを提供
2. **自動ライフサイクル管理**: ログイン/ログアウトに応じてアプリの起動・停止を自動制御
3. **リバースプロキシ**: nginx-ingressを使用してユーザーのアプリへの外部アクセスを提供
4. **保守機能**: 管理者による手動操作とシステム保守機能

## セットアップ手順

### 1. 前提条件

```bash
# Kubernetesクラスターとkubectlの設定
kubectl cluster-info

# Helmのインストール
helm version

# nginx-ingress controllerのインストール
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.1/deploy/static/provider/cloud/deploy.yaml
```

### 2. Gemのインストール

```bash
# Gemfileに追加
echo 'gem "kubeclient"' >> Gemfile
echo 'gem "sidekiq"' >> Gemfile
echo 'gem "whenever", require: false' >> Gemfile
bundle install
```

### 3. Service Account とRBACの設定

```bash
# Service Account作成
kubectl apply -f config/k8s/rbac.yaml

# Service Account Tokenの取得
kubectl create token rails-k8s-controller > k8s-token.txt
```

### 4. 環境変数の設定

```bash
# .env または環境変数として設定
export HELM_CHART_PATH="./helm-charts/user-app"
export APP_BASE_DOMAIN="apps.yourdomain.com"

# Kubernetes API設定
export K8S_API_ENDPOINT="https://your-k8s-cluster.com"
export K8S_TOKEN="$(cat k8s-token.txt)"
export K8S_VERIFY_SSL="true"

# または、開発環境では
export K8S_API_ENDPOINT="$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')"
```

### 5. Rails アプリケーションの設定

```bash
# データベースマイグレーション実行
rails db:migrate

# Kubernetes接続テスト
rails k8s:test_connection
```

### 6. 本番環境での展開（Kubernetes内）

```yaml
# k8s-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: rails-k8s-controller
spec:
  replicas: 1
  selector:
    matchLabels:
      app: rails-k8s-controller
  template:
    metadata:
      labels:
        app: rails-k8s-controller
    spec:
      serviceAccountName: rails-k8s-controller
      containers:
      - name: rails-app
        image: your-registry/rails-k8s-controller:latest
        env:
        - name: K8S_API_ENDPOINT
          value: "https://kubernetes.default.svc"
        - name: DATABASE_URL
          valueFrom:
            secretKeyRef:
              name: db-secret
              key: url
        volumeMounts:
        - name: service-account-token
          mountPath: /var/run/secrets/kubernetes.io/serviceaccount
          readOnly: true
      volumes:
      - name: service-account-token
        projected:
          sources:
          - serviceAccountToken:
              path: token
              expirationSeconds: 3600
```

## Gem版での主な変更点

### 1. コマンドラインからRuby APIへ

**従来 (コマンドライン)**:
```ruby
kubectl_command("kubectl get pods --namespace=#{namespace}")
```

**新版 (kubeclient gem)**:
```ruby
k8s_client.get_pods(namespace: namespace)
```

### 2. エラーハンドリングの改善

```ruby
begin
  deployment = k8s_apps_client.get_deployment(name, namespace)
  deployment.spec.replicas = replicas
  k8s_apps_client.update_deployment(deployment)
rescue Kubeclient::HttpError => e
  Rails.logger.error "Kubernetes API error: #{e.message}"
  raise K8sError, e.message
end
```

### 3. 認証方法の選択

```ruby
# Service Account Token (推奨)
auth_options: { bearer_token: ENV['K8S_TOKEN'] }

# Basic認証
auth_options: { username: 'user', password: 'pass' }

# kubeconfig (開発環境)
auth_options: {} # 自動的にkubeconfigを使用
```

## 使用方法

### 開発環境での接続テスト

```bash
# Kubernetes接続確認
rails k8s:test_connection

# クラスター情報表示
rails k8s:cluster_info

# リアルタイム監視
rails k8s:monitor[123]
```

### ユーザーアプリの操作

```ruby
# Railsコンソールで
user = User.find(123)
service = K8s::UserAppService.new(user)

# kubeclient gem を直接使用した操作
status = service.app_status
# => API経由で直接Kubernetesから状態を取得

# ログ取得（複数Pod対応）
logs = service.app_logs(lines: 50)
# => 各Podからログを取得してマージ
```

### 管理者機能

```ruby
maintenance = K8s::MaintenanceService.new

# 孤立リソースの検出（Label Selectorを使用）
orphaned = maintenance.cleanup_orphaned_resources

# クラスターリソースの詳細情報
resources = maintenance.get_cluster_resources
```

## パフォーマンスと信頼性の向上

### 1. API効率化

```ruby
# 一度の API呼び出しで複数リソース取得
namespaces = k8s_client.get_namespaces(label_selector: 'user-namespace=true')

# Kubernetes Watchを使用したリアルタイム更新
watcher = k8s_client.watch_pods(namespace: namespace)
watcher.each do |notice|
  puts "Pod #{notice.object.metadata.name}: #{notice.type}"
end
```

### 2. コネクションプーリング

```ruby
# Base Serviceでクライアントを再利用
def k8s_client
  @k8s_client ||= Kubeclient::Client.new(...)
end
```

### 3. 非同期処理の活用

```ruby
# バックグラウンドでの長時間操作
UserAppDeployJob.perform_later(user_id)

# 並列処理でのスケールアップ
users.find_in_batches do |user_batch|
  user_batch.each do |user|
    UserAppStartJob.perform_later(user.id)
  end
end
```

## トラブルシューティング

### 1. API接続エラー

```bash
# 接続テスト
rails k8s:test_connection

# 認証確認
kubectl auth can-i get pods --as=system:serviceaccount:default:rails-k8s-controller
```

### 2. 権限エラー

```yaml
# RBAC権限の確認と追加
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: rails-k8s-controller
rules:
- apiGroups: [""]
  resources: ["pods/log"]  # ログ取得権限を追加
  verbs: ["get"]
```

### 3. パフォーマンス問題

```ruby
# API呼び出し頻度の監視
Rails.logger.debug "K8s API call: #{Time.current}"

# レスポンス時間の測定
start_time = Time.current
result = k8s_client.get_pods(namespace: namespace)
Rails.logger.info "API call took: #{Time.current - start_time}s"
```

## 本番運用のベストプラクティス

### 1. 監視とアラート

```ruby
# ヘルスチェック
def kubernetes_healthy?
  k8s_client.api_valid?
rescue => e
  Rails.logger.error "K8s health check failed: #{e.message}"
  false
end
```

### 2. リソース制限

```ruby
# API呼び出し制限
class K8s::BaseService
  include ActionController::Live # SSE用

  def with_rate_limit(&block)
    # Rate limiting logic
    yield
  end
end
```

### 3. セキュリティ

```yaml
# Network Policy例
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: rails-controller-netpol
spec:
  podSelector:
    matchLabels:
      app: rails-k8s-controller
  egress:
  - to:
    - namespaceSelector: {}
    ports:
    - protocol: TCP
      port: 443  # Kubernetes API
```

`kubeclient` gemを使用することで、より安定的でパフォーマンスの良いKubernetes制御が可能になり、エラーハンドリングも向上します。

2. **手動操作**
   - 強制デプロイ: 問題のあるアプリを強制的に再デプロイ
   - 強制削除: 問題のあるアプリを強制的に削除
   - 孤立リソースクリーンアップ: ユーザーが削除されたが残っているリソースを削除

### Rakeタスクによる操作

```bash
# 特定ユーザーのアプリをデプロイ
rails k8s:deploy_user_app[123]

# 特定ユーザーのアプリを削除
rails k8s:undeploy_user_app[123]

# アプリの起動
rails k8s:start_user_app[123]

# アプリの停止
rails k8s:stop_user_app[123]

# アプリの状態確認
rails k8s:status[123]

# 全ユーザーアプリの一覧
rails k8s:list_all

# 孤立リソースのクリーンアップ
rails k8s:cleanup

# クラスター情報の確認
rails k8s:cluster_info
```

### Railsコンソールでの操作

```ruby
# 特定ユーザーのサービス取得
user = User.find(123)
service = K8s::UserAppService.new(user)

# アプリの状態確認
service.app_status
# => "running", "stopped", "not_deployed", "starting", "error"

# アプリのデプロイ
result = service.deploy_user_app
# => { namespace: "user-123-a1b2", release_name: "user-app-123", url: "https://user-123.apps.yourdomain.com" }

# アプリの起動
service.start_user_app

# アプリの停止
service.stop_user_app

# アプリの再起動
service.restart_user_app

# アプリの削除
service.undeploy_user_app

# ログの取得
logs = service.app_logs(lines: 100)
```

### 保守作業

```ruby
# 保守サービスの使用
maintenance = K8s::MaintenanceService.new

# 全ユーザーアプリの一覧取得
apps = maintenance.list_all_user_apps

# 孤立リソースの確認と削除
orphaned = maintenance.cleanup_orphaned_resources

# 特定ユーザーのアプリを強制デプロイ
maintenance.force_deploy_user_app(123)

# 特定ユーザーのアプリを強制削除
maintenance.force_undeploy_user_app(123)

# クラスターリソースの確認
resources = maintenance.get_cluster_resources
```

## 自動化機能

### セッション管理による自動制御

```ruby
# ユーザーログイン時の自動処理
class ApplicationController < ActionController::Base
  after_action :schedule_app_lifecycle

  private

  def schedule_app_lifecycle
    if user_signed_in? && session[:just_signed_in]
      current_user.start_app_on_login  # アプリ自動起動
    end
  end
end

# セッションタイムアウト監視（定期実行）
# config/schedule.rb
every 5.minutes do
  runner "SessionTimeoutMonitorJob.perform_later"
end
```

### バックグラウンドジョブ

```ruby
# アプリのデプロイ（非同期）
UserAppDeployJob.perform_later(user_id)

# アプリの起動（非同期）
UserAppStartJob.perform_later(user_id)

# アプリの停止（非同期）
UserAppStopJob.perform_later(user_id)

# リソースのクリーンアップ（非同期）
UserAppCleanupJob.perform_later(user_id)
```

## システム構成

### Kubernetesリソース構成

```
Cluster
├── Namespace: user-{user_id}-{suffix}
│   ├── Deployment: user-app-{user_id}
│   ├── Service: user-app-{user_id}
│   ├── Ingress: user-app-{user_id}-ingress
│   └── ServiceAccount: user-app-{user_id}
└── nginx-ingress-controller (共通)
```

### DNS構成

```
*.apps.yourdomain.com → nginx-ingress-controller
├── user-123.apps.yourdomain.com → user-123のアプリ
├── user-456.apps.yourdomain.com → user-456のアプリ
└── ...
```

### データベーススキーマ

```ruby
# users テーブルに追加されるカラム
class User < ApplicationRecord
  # k8s_namespace: ユーザー専用のnamespace名
  # k8s_release_name: Helmリリース名
  # app_url: アプリのアクセスURL
  # app_status: アプリの状態 (not_deployed, running, stopped, starting, error)
  # last_login_at: 最終ログイン時刻（セッションタイムアウト判定用）
end
```

## セキュリティ考慮事項

### 1. Kubernetes RBAC

```yaml
# Serviceアカウントの権限を最小限に制限
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: user-{user_id}-{suffix}
  name: user-app-role
rules:
- apiGroups: [""]
  resources: ["pods", "services"]
  verbs: ["get", "list"]
```

### 2. ネットワークポリシー

```yaml
# namespace間の通信を制限
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: user-app-netpol
  namespace: user-{user_id}-{suffix}
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: ingress-nginx
```

### 3. リソース制限

```yaml
# リソース使用量の制限
resources:
  limits:
    cpu: 500m
    memory: 512Mi
    ephemeral-storage: 1Gi
  requests:
    cpu: 100m
    memory: 256Mi
```

## 監視とログ

### 1. アプリケーションログ

```ruby
# ログの取得
service = K8s::UserAppService.new(user)
logs = service.app_logs(lines: 100)

# ログのリアルタイム監視
kubectl logs -f -l app=user-app-123 --namespace=user-123-a1b2
```

### 2. システム監視

```ruby
# クラスター全体のリソース監視
maintenance = K8s::MaintenanceService.new
resources = maintenance.get_cluster_resources

# 定期的な健康チェック
SessionTimeoutMonitorJob.perform_later  # 5分毎実行
```

### 3. エラーハンドリング

```ruby
begin
  service.deploy_user_app
rescue K8s::BaseService::K8sError => e
  Rails.logger.error "K8s operation failed: #{e.message}"
  # エラー通知やリトライロジック
  NotificationService.notify_admin(e)
end
```

## トラブルシューティング

### よくある問題と解決方法

#### 1. アプリがデプロイされない
```bash
# Helmの状態確認
helm list --all-namespaces

# namespaceの確認
kubectl get namespaces | grep user-

# ログの確認
rails k8s:status[user_id]
```

#### 2. アプリにアクセスできない
```bash
# Ingressの確認
kubectl get ingress --all-namespaces

# DNS解決の確認
nslookup user-123.apps.yourdomain.com

# nginx-ingress controllerのログ確認
kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx
```

#### 3. リソースリークの対処
```bash
# 孤立リソースのクリーンアップ
rails k8s:cleanup

# 手動でのnamespace削除
kubectl delete namespace user-123-a1b2 --force --grace-period=0
```

#### 4. パフォーマンス問題
```bash
# リソース使用量の確認
kubectl top pods --all-namespaces

# クラスター情報の確認
rails k8s:cluster_info

# 不要なアプリの停止
rails k8s:stop_user_app[inactive_user_id]
```

## カスタマイズ

### 1. Helmチャートのカスタマイズ
- `helm-charts/user-app/values.yaml` でデフォルト値を変更
- `helm-charts/user-app/templates/` でKubernetesリソースをカスタマイズ

### 2. セッション管理のカスタマイズ
```ruby
# config/application.rb
config.session_timeout_minutes = 60  # タイムアウト時間の変更
config.auto_deploy_user_apps = false  # 自動デプロイの無効化
```

### 3. リソース制限のカスタマイズ
```ruby
# app/services/k8s/user_app_service.rb
def build_helm_values
  {
    'resources.requests.memory' => '512Mi',  # メモリ要求量の変更
    'resources.limits.cpu' => '1000m'       # CPU制限の変更
  }
end
```

このシステムにより、Rails 8.0アプリケーションでユーザー毎に独立したKubernetesアプリを効率的に管理できます。
