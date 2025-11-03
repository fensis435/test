#!/bin/bash

set -e

echo "=== JWT認証統合デプロイスクリプト ==="

# 環境変数の確認
if [ -z "$GRAFANA_ADMIN_PASSWORD" ]; then
    echo "Error: GRAFANA_ADMIN_PASSWORD is not set"
    exit 1
fi

# 1. Namespaceの作成
echo "1. Creating namespaces..."
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace kubernetes-dashboard --dry-run=client -o yaml | kubectl apply -f -

# 2. Grafanaのデプロイ
echo "2. Deploying Grafana..."
kubectl apply -f grafana-config.yaml

# 3. Grafana Admin Tokenの作成（初回のみ）
echo "3. Setting up Grafana admin token..."
GRAFANA_POD=$(kubectl get pods -n monitoring -l app=grafana -o jsonpath='{.items[0].metadata.name}')

# Grafanaが起動するまで待機
echo "Waiting for Grafana to be ready..."
kubectl wait --for=condition=ready pod -l app=grafana -n monitoring --timeout=300s

# Admin APIキーの作成
GRAFANA_TOKEN=$(kubectl exec -n monitoring $GRAFANA_POD -- grafana-cli admin reset-admin-password "$GRAFANA_ADMIN_PASSWORD" 2>&1)

# トークンをSecretとして保存
kubectl create secret generic grafana-admin-token \
  --from-literal=token="$GRAFANA_ADMIN_PASSWORD" \
  -n default \
  --dry-run=client -o yaml | kubectl apply -f -

# 4. Kubernetes DashboardのRBACセットアップ
echo "4. Setting up Kubernetes Dashboard RBAC..."
kubectl apply -f k8s-dashboard-rbac.yaml

# 5. ServiceAccountトークンの取得と確認
echo "5. Retrieving ServiceAccount tokens..."

# Admin token
ADMIN_TOKEN=$(kubectl get secret dashboard-admin-sa-token -n kubernetes-dashboard -o jsonpath='{.data.token}' | base64 -d)
echo "Admin token created (first 20 chars): ${ADMIN_TOKEN:0:20}..."

# Viewer token
VIEWER_TOKEN=$(kubectl get secret dashboard-viewer-sa-token -n kubernetes-dashboard -o jsonpath='{.data.token}' | base64 -d)
echo "Viewer token created (first 20 chars): ${VIEWER_TOKEN:0:20}..."

# トークンをRails用のSecretとして保存
kubectl create secret generic k8s-sa-tokens \
  --from-literal=admin-token="$ADMIN_TOKEN" \
  --from-literal=viewer-token="$VIEWER_TOKEN" \
  -n default \
  --dry-run=client -o yaml | kubectl apply -f -

# 6. Ingressのデプロイ
echo "6. Deploying Ingress resources..."
kubectl apply -f grafana-ingress.yaml

# 7. Railsアプリケーションの環境変数を更新
echo "7. Updating Rails application configuration..."
kubectl set env deployment/rails-app \
  GRAFANA_API_URL="http://grafana.monitoring.svc.cluster.local:3000" \
  GRAFANA_ADMIN_TOKEN="$GRAFANA_ADMIN_PASSWORD" \
  K8S_API_URL="https://kubernetes.default.svc" \
  -n default

# Railsポッドの再起動
kubectl rollout restart deployment/rails-app -n default
kubectl rollout status deployment/rails-app -n default

# 8. 動作確認
echo ""
echo "=== デプロイ完了 ==="
echo ""
echo "アクセスURL:"
echo "  Grafana: https://grafana.yourdomain.com"
echo "  Kubernetes Dashboard: https://k8s-dashboard.yourdomain.com"
echo ""
echo "次のステップ:"
echo "1. DNSレコードが正しく設定されていることを確認"
echo "2. TLS証明書が発行されていることを確認"
echo "3. Railsアプリケーションにログインしてテスト"
echo "4. Grafana/K8s Dashboardへのアクセスをテスト"
echo ""
echo "トラブルシューティング:"
echo "  kubectl logs -n default -l app=rails-app"
echo "  kubectl logs -n monitoring -l app=grafana"
echo "  kubectl get ingress -A"
