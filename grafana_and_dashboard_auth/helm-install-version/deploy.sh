#!/bin/bash

set -e

echo "=== JWT認証統合デプロイスクリプト (Helm版) ==="

# 色の定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 環境変数の確認
if [ -z "$GRAFANA_ADMIN_PASSWORD" ]; then
    echo -e "${RED}Error: GRAFANA_ADMIN_PASSWORD is not set${NC}"
    exit 1
fi

# Helmリポジトリの追加
echo -e "${GREEN}1. Adding Helm repositories...${NC}"
helm repo add grafana https://grafana.github.io/helm-charts
helm repo add kubernetes-dashboard https://kubernetes.github.io/dashboard/
helm repo update

# Namespaceの作成
echo -e "${GREEN}2. Creating namespaces...${NC}"
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace kubernetes-dashboard --dry-run=client -o yaml | kubectl apply -f -

# Grafanaのインストール
echo -e "${GREEN}3. Installing Grafana...${NC}"
helm upgrade --install grafana grafana/grafana \
  --namespace monitoring \
  --values grafana-values.yaml \
  --set adminPassword="$GRAFANA_ADMIN_PASSWORD" \
  --wait \
  --timeout 10m

# Grafanaの起動確認
echo -e "${YELLOW}Waiting for Grafana to be ready...${NC}"
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=grafana -n monitoring --timeout=300s

# Grafana Admin APIキーの作成とSecret保存
echo -e "${GREEN}4. Setting up Grafana admin credentials...${NC}"
GRAFANA_POD=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana -o jsonpath='{.items[0].metadata.name}')

# Admin APIキーを作成（既存の場合はスキップ）
if ! kubectl get secret grafana-admin-token -n default &> /dev/null; then
    kubectl create secret generic grafana-admin-token \
      --from-literal=password="$GRAFANA_ADMIN_PASSWORD" \
      -n default
    echo -e "${GREEN}Grafana admin token secret created${NC}"
else
    echo -e "${YELLOW}Grafana admin token secret already exists${NC}"
fi

# Kubernetes DashboardのRBACセットアップ
echo -e "${GREEN}5. Setting up Kubernetes Dashboard RBAC...${NC}"
kubectl apply -f k8s-dashboard-rbac.yaml

# Kubernetes Dashboardのインストール
echo -e "${GREEN}6. Installing Kubernetes Dashboard...${NC}"
helm upgrade --install kubernetes-dashboard kubernetes-dashboard/kubernetes-dashboard \
  --namespace kubernetes-dashboard \
  --values kubernetes-dashboard-values.yaml \
  --wait \
  --timeout 10m

# Dashboardの起動確認
echo -e "${YELLOW}Waiting for Kubernetes Dashboard to be ready...${NC}"
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=kubernetes-dashboard -n kubernetes-dashboard --timeout=300s

# ServiceAccountトークンの取得
echo -e "${GREEN}7. Retrieving ServiceAccount tokens...${NC}"

# トークンが作成されるまで少し待つ
sleep 5

# Admin token
if kubectl get secret dashboard-admin-sa-token -n kubernetes-dashboard &> /dev/null; then
    ADMIN_TOKEN=$(kubectl get secret dashboard-admin-sa-token -n kubernetes-dashboard -o jsonpath='{.data.token}' | base64 -d)
    echo -e "${GREEN}Admin token retrieved (first 20 chars): ${ADMIN_TOKEN:0:20}...${NC}"
else
    echo -e "${RED}Warning: Admin token secret not found${NC}"
    ADMIN_TOKEN=""
fi

# Viewer token
if kubectl get secret dashboard-viewer-sa-token -n kubernetes-dashboard &> /dev/null; then
    VIEWER_TOKEN=$(kubectl get secret dashboard-viewer-sa-token -n kubernetes-dashboard -o jsonpath='{.data.token}' | base64 -d)
    echo -e "${GREEN}Viewer token retrieved (first 20 chars): ${VIEWER_TOKEN:0:20}...${NC}"
else
    echo -e "${RED}Warning: Viewer token secret not found${NC}"
    VIEWER_TOKEN=""
fi

# Editor token
if kubectl get secret dashboard-editor-sa-token -n kubernetes-dashboard &> /dev/null; then
    EDITOR_TOKEN=$(kubectl get secret dashboard-editor-sa-token -n kubernetes-dashboard -o jsonpath='{.data.token}' | base64 -d)
    echo -e "${GREEN}Editor token retrieved (first 20 chars): ${EDITOR_TOKEN:0:20}...${NC}"
else
    echo -e "${RED}Warning: Editor token secret not found${NC}"
    EDITOR_TOKEN=""
fi

# トークンをRails用のSecretとして保存
echo -e "${GREEN}8. Storing ServiceAccount tokens for Rails...${NC}"
kubectl create secret generic k8s-sa-tokens \
  --from-literal=admin-token="$ADMIN_TOKEN" \
  --from-literal=viewer-token="$VIEWER_TOKEN" \
  --from-literal=editor-token="$EDITOR_TOKEN" \
  -n default \
  --dry-run=client -o yaml | kubectl apply -f -

# Railsアプリケーションの環境変数を更新
echo -e "${GREEN}9. Updating Rails application configuration...${NC}"
if kubectl get deployment rails-app -n default &> /dev/null; then
    kubectl set env deployment/rails-app \
      GRAFANA_API_URL="http://grafana.monitoring.svc.cluster.local:80" \
      GRAFANA_ADMIN_PASSWORD="$GRAFANA_ADMIN_PASSWORD" \
      K8S_API_URL="https://kubernetes.default.svc" \
      -n default

    # Railsポッドの再起動
    kubectl rollout restart deployment/rails-app -n default
    kubectl rollout status deployment/rails-app -n default --timeout=5m
else
    echo -e "${YELLOW}Warning: rails-app deployment not found. Skipping Rails configuration.${NC}"
fi

# 設定情報の取得
echo -e "${GREEN}10. Retrieving service information...${NC}"
GRAFANA_INGRESS=$(kubectl get ingress -n monitoring -o jsonpath='{.items[0].spec.rules[0].host}' 2>/dev/null || echo "Not configured")
DASHBOARD_INGRESS=$(kubectl get ingress -n kubernetes-dashboard -o jsonpath='{.items[0].spec.rules[0].host}' 2>/dev/null || echo "Not configured")

# 動作確認コマンドの生成
echo ""
echo -e "${GREEN}=== デプロイ完了 ===${NC}"
echo ""
echo -e "${YELLOW}インストールされたコンポーネント:${NC}"
echo "  ✓ Grafana (monitoring namespace)"
echo "  ✓ Kubernetes Dashboard (kubernetes-dashboard namespace)"
echo "  ✓ RBAC設定"
echo "  ✓ ServiceAccount tokens"
echo ""
echo -e "${YELLOW}アクセスURL:${NC}"
echo "  Grafana: https://${GRAFANA_INGRESS}"
echo "  Kubernetes Dashboard: https://${DASHBOARD_INGRESS}"
echo ""
echo -e "${YELLOW}Helm Releases:${NC}"
helm list -n monitoring
helm list -n kubernetes-dashboard
echo ""
echo -e "${YELLOW}次のステップ:${NC}"
echo "1. DNSレコードが正しく設定されていることを確認"
echo "   $ dig ${GRAFANA_INGRESS}"
echo "   $ dig ${DASHBOARD_INGRESS}"
echo ""
echo "2. TLS証明書が発行されていることを確認"
echo "   $ kubectl get certificate -A"
echo ""
echo "3. Railsアプリケーションにログインしてテスト"
echo "   ブラウザで https://yourdomain.com/login にアクセス"
echo ""
echo "4. Grafana/K8s Dashboardへのアクセスをテスト"
echo "   ログイン後、各URLにアクセスして自動ログインを確認"
echo ""
echo -e "${YELLOW}トラブルシューティング:${NC}"
echo "  # Grafanaのログ確認"
echo "  kubectl logs -n monitoring -l app.kubernetes.io/name=grafana"
echo ""
echo "  # Kubernetes Dashboardのログ確認"
echo "  kubectl logs -n kubernetes-dashboard -l app.kubernetes.io/name=kubernetes-dashboard"
echo ""
echo "  # Railsアプリのログ確認"
echo "  kubectl logs -n default -l app=rails-app"
echo ""
echo "  # Ingressの確認"
echo "  kubectl get ingress -A"
echo "  kubectl describe ingress -n monitoring"
echo "  kubectl describe ingress -n kubernetes-dashboard"
echo ""
echo "  # 認証エンドポイントのテスト"
echo "  kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- \\"
echo "    curl -v http://rails-service.default.svc.cluster.local/auth/verify"
echo ""
echo -e "${YELLOW}アンインストール方法:${NC}"
echo "  helm uninstall grafana -n monitoring"
echo "  helm uninstall kubernetes-dashboard -n kubernetes-dashboard"
echo "  kubectl delete -f k8s-dashboard-rbac.yaml"
echo ""
echo -e "${GREEN}デプロイが完了しました！${NC}"