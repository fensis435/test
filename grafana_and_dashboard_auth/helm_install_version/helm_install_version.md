Helm installを前提とした構成に修正します。完成しました！Helm installを前提とした構成に変更しました。

## 主な変更点

### 1. **Grafana Helm Values** (`grafana-values.yaml`)
- 公式Grafana Helm Chartの設定形式に対応
- Auth Proxy設定を`grafana.ini`セクションに記述
- Ingress、Persistence、Resourcesなどを統合

### 2. **Kubernetes Dashboard Helm Values** (`kubernetes-dashboard-values.yaml`)
- 公式Dashboard Helm Chartの設定形式に対応
- `--enable-skip-login`などのextraArgsを設定
- メトリクススクレーパーも含む

### 3. **RBAC設定の分離** (`k8s-dashboard-rbac.yaml`)
- Helm Chartとは別に管理する追加RBAC
- Admin/Editor/Viewer用のServiceAccountとトークン
- ClusterRoleとClusterRoleBindingを定義

### 4. **デプロイスクリプトの改善** (`deploy.sh`)
- `helm upgrade --install`を使用
- カラー出力で見やすく
- エラーハンドリングの強化
- 詳細なトラブルシューティングコマンド付き

### 5. **Rails Deployment** (`rails-deployment.yaml`)
- ServiceAccountとRBACを追加
- Kubernetes APIへのアクセス権限を付与
- 環境変数でトークンを管理

### 6. **詳細なドキュメント** (`INSTALLATION.md`)
- 手動インストール手順
- トラブルシューティングガイド
- アップグレード/アンインストール方法

## 使用方法

```bash
# 1. 環境変数設定
export GRAFANA_ADMIN_PASSWORD="your-secure-password"

# 2. values.yamlのドメイン部分を編集
# grafana-values.yaml と kubernetes-dashboard-values.yaml

# 3. デプロイ実行
chmod +x deploy.sh
./deploy.sh
```

これでHelm経由で簡単にデプロイできるようになりました！