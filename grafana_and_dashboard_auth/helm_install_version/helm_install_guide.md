# JWT認証統合デプロイガイド (Helm版)

このガイドでは、Helmを使用してGrafanaとKubernetes DashboardをRailsのJWT認証と統合する方法を説明します。

## 前提条件

- Kubernetes クラスター (v1.24+)
- Helm 3.x
- kubectl CLI
- nginx-ingress-controller
- cert-manager (TLS証明書用)
- Railsアプリケーションがデプロイ済み

## ディレクトリ構成

```
.
├── grafana-values.yaml                  # Grafana Helm values
├── kubernetes-dashboard-values.yaml     # K8s Dashboard Helm values
├── k8s-dashboard-rbac.yaml             # 追加のRBAC設定
├── rails-deployment.yaml                # Railsアプリデプロイメント
├── deploy.sh                            # 自動デプロイスクリプト
└── INSTALLATION.md                      # このファイル
```

## インストール手順

### 1. 環境変数の設定

```bash
export GRAFANA_ADMIN_PASSWORD="your-strong-password"
export DOMAIN="yourdomain.com"
```

### 2. values.yamlファイルの編集

#### grafana-values.yaml
```yaml
# ドメインを変更
grafana.ini:
  server:
    root_url: https://grafana.${DOMAIN}

ingress:
  hosts:
    - grafana.${DOMAIN}
  tls:
    - hosts:
        - grafana.${DOMAIN}
```

#### kubernetes-dashboard-values.yaml
```yaml
# ドメインを変更
ingress:
  hosts:
    - k8s-dashboard.${DOMAIN}
  tls:
    - hosts:
        - k8s-dashboard.${DOMAIN}
```

### 3. 自動デプロイスクリプトの実行

```bash
chmod +x deploy.sh
./deploy.sh
```

または、手動でステップバイステップでインストール：

### 4. 手動インストール

#### 4.1 Helmリポジトリの追加

```bash
helm repo add grafana https://grafana.github.io/helm-charts
helm repo add kubernetes-dashboard https://kubernetes.github.io/dashboard/
helm repo update
```

#### 4.2 Namespaceの作成

```bash
kubectl create namespace monitoring
kubectl create namespace kubernetes-dashboard
```

#### 4.3 Grafanaのインストール

```bash
helm install grafana grafana/grafana \
  --namespace monitoring \
  --values grafana-values.yaml \
  --set adminPassword="${GRAFANA_ADMIN_PASSWORD}"
```

#### 4.4 Kubernetes Dashboard RBACの適用

```bash
kubectl apply -f k8s-dashboard-rbac.yaml
```

#### 4.5 Kubernetes Dashboardのインストール

```bash
helm install kubernetes-dashboard kubernetes-dashboard/kubernetes-dashboard \
  --namespace kubernetes-dashboard \
  --values kubernetes-dashboard-values.yaml
```

#### 4.6 ServiceAccountトークンの取得

```bash
# Admin token
kubectl get secret dashboard-admin-sa-token \
  -n kubernetes-dashboard \
  -o jsonpath='{.data.token}' | base64 -d

# Viewer token
kubectl get secret dashboard-viewer-sa-token \
  -n kubernetes-dashboard \
  -o jsonpath='{.data.token}' | base64 -d

# Editor token
kubectl get secret dashboard-editor-sa-token \
  -n kubernetes-dashboard \
  -o jsonpath='{.data.token}' | base64 -d
```

#### 4.7 トークンをSecretとして保存

```bash
kubectl create secret generic k8s-sa-tokens \
  --from-literal=admin-token="$(kubectl get secret dashboard-admin-sa-token -n kubernetes-dashboard -o jsonpath='{.data.token}' | base64 -d)" \
  --from-literal=viewer-token="$(kubectl get secret dashboard-viewer-sa-token -n kubernetes-dashboard -o jsonpath='{.data.token}' | base64 -d)" \
  --from-literal=editor-token="$(kubectl get secret dashboard-editor-sa-token -n kubernetes-dashboard -o jsonpath='{.data.token}' | base64 -d)" \
  -n default
```

#### 4.8 Railsアプリケーションのデプロイ

```bash
# Secretの作成（事前に値を変更してください）
kubectl apply -f rails-deployment.yaml

# または既存のdeploymentを更新
kubectl set env deployment/rails-app \
  GRAFANA_API_URL="http://grafana.monitoring.svc.cluster.local:80" \
  K8S_API_URL="https://kubernetes.default.svc" \
  -n default
```

## 確認方法

### 1. Podの状態確認

```bash
# Grafana
kubectl get pods -n monitoring

# Kubernetes Dashboard
kubectl get pods -n kubernetes-dashboard

# Rails
kubectl get pods -n default
```

### 2. Ingressの確認

```bash
kubectl get ingress -A
```

### 3. 認証エンドポイントのテスト

```bash
# クラスタ内からテスト
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- \
  curl -v http://rails-service.default.svc.cluster.local/auth/verify
```

### 4. ブラウザでのテスト

1. Railsアプリケーションにログイン: `https://yourdomain.com/login`
2. Grafanaにアクセス: `https://grafana.yourdomain.com`
   - 自動的にログインされることを確認
3. Kubernetes Dashboardにアクセス: `https://k8s-dashboard.yourdomain.com`
   - 認証プロキシを経由してアクセスできることを確認

## トラブルシューティング

### Grafanaにログインできない

```bash
# Grafanaのログ確認
kubectl logs -n monitoring -l app.kubernetes.io/name=grafana

# Grafana設定確認
kubectl get configmap -n monitoring grafana -o yaml

# 認証ヘッダーの確認
kubectl logs -n ingress-nginx -l app.kubernetes.io/component=controller | grep X-Auth
```

### Kubernetes Dashboardにアクセスできない

```bash
# Dashboardのログ確認
kubectl logs -n kubernetes-dashboard -l app.kubernetes.io/name=kubernetes-dashboard

# ServiceAccountトークンの確認
kubectl get secret dashboard-admin-sa-token -n kubernetes-dashboard -o yaml
```

### 認証プロキシが動作しない

```bash
# Rails認証エンドポイントの確認
kubectl exec -n default -it $(kubectl get pod -n default -l app=rails-app -o jsonpath='{.items[0].metadata.name}') -- curl localhost:3000/auth/verify

# Ingress設定の確認
kubectl describe ingress -n monitoring grafana
kubectl describe ingress -n kubernetes-dashboard
```

### TLS証明書が発行されない

```bash
# Certificate確認
kubectl get certificate -A

# cert-managerのログ確認
kubectl logs -n cert-manager -l app=cert-manager
```

## アップグレード

### Grafanaのアップグレード

```bash
helm upgrade grafana grafana/grafana \
  --namespace monitoring \
  --values grafana-values.yaml \
  --set adminPassword="${GRAFANA_ADMIN_PASSWORD}"
```

### Kubernetes Dashboardのアップグレード

```bash
helm upgrade kubernetes-dashboard kubernetes-dashboard/kubernetes-dashboard \
  --namespace kubernetes-dashboard \
  --values kubernetes-dashboard-values.yaml
```

## アンインストール

```bash
# Helm releases
helm uninstall grafana -n monitoring
helm uninstall kubernetes-dashboard -n kubernetes-dashboard

# RBAC
kubectl delete -f k8s-dashboard-rbac.yaml

# Secrets
kubectl delete secret k8s-sa-tokens -n default
kubectl delete secret grafana-admin-token -n default

# Namespaces（必要に応じて）
kubectl delete namespace monitoring
kubectl delete namespace kubernetes-dashboard
```

## セキュリティのベストプラクティス

1. **強力なパスワードの使用**
   - `GRAFANA_ADMIN_PASSWORD`は複雑なパスワードを設定

2. **JWT Secretの保護**
   - `rails-secrets`のSecretを適切に管理

3. **HTTPS必須**
   - cert-managerでTLS証明書を自動更新

4. **RBAC最小権限**
   - 各ServiceAccountには必要最小限の権限のみ付与

5. **トークンのローテーション**
   - 定期的にServiceAccountトークンを再生成

6. **監査ログの有効化**
   - Kubernetes監査ログを有効にして不正アクセスを検知

## 参考リンク

- [Grafana Helm Chart](https://github.com/grafana/helm-charts/tree/main/charts/grafana)
- [Kubernetes Dashboard Helm Chart](https://github.com/kubernetes/dashboard/tree/master/charts/kubernetes-dashboard)
- [Grafana Auth Proxy Documentation](https://grafana.com/docs/grafana/latest/setup-grafana/configure-security/configure-authentication/auth-proxy/)
- [Kubernetes RBAC](https://kubernetes.io/docs/reference/access-authn-authz/rbac/)
