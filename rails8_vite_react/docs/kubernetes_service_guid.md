Rails 8.0のapp/services配下に配置するKubernetes client libraryを使った包括的な便利操作関数群です。
以下のようにカテゴリーごとにファイルを分けて整理しています：

## 📁 ファイル構成

### 1. **BaseService** (`app/services/kubernetes/base_service.rb`)
- 全サービスの基底クラス
- K8s clientの初期化と共通メソッド
- エラーハンドリングとヘルパーメソッド

### 2. **PodService** (`app/services/kubernetes/pod_service.rb`)
- Pod の作成、取得、削除、ログ取得
- Pod実行コマンド、ポートフォワーディング
- Pod状態監視とready待機

### 3. **DeploymentService** (`app/services/kubernetes/deployment_service.rb`)
- Deployment の管理操作
- スケーリング、リスタート、ローリングアップデート
- ロールバック機能

### 4. **ServiceService** (`app/services/kubernetes/service_service.rb`)
- Service の作成と管理
- ClusterIP、NodePort、LoadBalancer対応
- Headlessサービスの作成

### 5. **ConfigService** (`app/services/kubernetes/config_service.rb`)
- ConfigMapとSecretの管理
- Docker registry secret、TLS secret、Basic auth secret
- ファイルからの作成機能

### 6. **IngressService** (`app/services/kubernetes/ingress_service.rb`)
- Ingress リソースの管理
- TLS終端、パスルーティング
- 簡単なIngress作成ヘルパー

### 7. **JobService** (`app/services/kubernetes/job_service.rb`)
- JobとCronJobの管理
- ジョブ完了待機、ログ取得
- CronJobの手動実行、一時停止

### 8. **NamespaceService & RbacService** (`app/services/kubernetes/namespace_service.rb`)
- Namespace管理とリソースクォータ設定
- RBAC (ServiceAccount, Role, RoleBinding等)
- 一般的なロールパターンのビルダー

### 9. **VolumeService** (`app/services/kubernetes/volume_service.rb`)
- PV、PVC、StorageClassの管理
- ボリュームスナップショット
- 各種ストレージタイプ対応

### 10. **AutoscalingService & MonitoringService** (`app/services/kubernetes/autoscaling_service.rb`)
- HPA (Horizontal Pod Autoscaler) 管理
- リソース使用量の監視と分析
- クラスターヘルスチェック

### 11. **NodeService** (`app/services/kubernetes/node_service.rb`)
- ノード管理（drain、cordon、uncordon）
- ノードのtaint/untaint、ラベリング
- リソース使用量の取得

### 12. **UsageExamples** (`app/services/kubernetes/usage_examples.rb`)
- 実践的な使用例とパターン
- Blue-Green デプロイメント
- アプリケーションのヘルスチェック

## 🚀 使用方法の例

```ruby
# Webアプリケーションのデプロイ
result = Kubernetes::UsageExamples.deploy_web_app(
  'my-web-app',
  'nginx:latest',
  namespace: 'production',
  replicas: 5
)

# アプリケーションの健康状態チェック
health = Kubernetes::UsageExamples.check_application_health(
  'my-web-app',
  namespace: 'production'
)

# クラスター全体のリソース使用量分析
analysis = Kubernetes::MonitoringService.analyze_cluster_resources

# ノードのメンテナンス
Kubernetes::NodeService.drain_node('worker-node-1', force: true)
```

## 🔧 必要なGem

Gemfileに以下を追加してください：

```ruby
gem 'k8s-client'
```

これらのサービスクラスは、Rails 8.0のビジネスロジック層でKubernetesの操作を簡単かつ安全に実行するための包括的なソリューションです。各サービスは独立しており、必要な機能だけを選択して使用することも可能です。
