#!/usr/bin/env bash
# =============================================================================
# ops.sh - 運用コマンド集
# SSM で踏み台EC2にログインし、このスクリプトを実行する
# 使い方: ./ops.sh <command> [options]
# =============================================================================
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-private-eks-cluster}"
AWS_REGION="${AWS_REGION:-ap-northeast-1}"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

log()  { echo -e "\033[1;34m[OPS]\033[0m $*"; }
warn() { echo -e "\033[1;33m[WARN]\033[0m $*"; }

# kubeconfig 更新
setup_kubeconfig() {
  aws eks update-kubeconfig \
    --name "${CLUSTER_NAME}" \
    --region "${AWS_REGION}"
}

# ---------------------------------------------------------------------------
# コマンド: status - クラスタ全体の状態確認
# ---------------------------------------------------------------------------
cmd_status() {
  log "=== クラスタ状態確認 ==="
  echo ""
  echo "--- ノード ---"
  kubectl get nodes -o wide
  echo ""
  echo "--- Pod (全namespace, 異常のみ) ---"
  kubectl get pods -A | grep -v -E "Running|Completed" | grep -v NAME || echo "全Pod正常"
  echo ""
  echo "--- NodePool (Karpenter) ---"
  kubectl get nodepools 2>/dev/null || echo "Karpenterなし"
  echo ""
  echo "--- ArgoCD Application ---"
  kubectl get applications -n argocd 2>/dev/null || echo "ArgoCDなし"
  echo ""
  echo "--- StorageClass ---"
  kubectl get sc
  echo ""
  echo "--- PVC ---"
  kubectl get pvc -A
}

# ---------------------------------------------------------------------------
# コマンド: logs - ログ確認
# ---------------------------------------------------------------------------
cmd_logs() {
  local ns="${1:-app}"
  local app="${2:-rails-app}"
  log "=== ログ確認: ${ns}/${app} ==="
  kubectl logs -n "${ns}" -l "app.kubernetes.io/name=${app}" \
    --tail=100 -f
}

# ---------------------------------------------------------------------------
# コマンド: argocd-sync - ArgoCD 手動同期
# ---------------------------------------------------------------------------
cmd_argocd_sync() {
  local app="${1:-}"
  if [ -z "${app}" ]; then
    log "全アプリケーションを同期..."
    kubectl get applications -n argocd -o name | while read -r app_name; do
      kubectl patch "${app_name}" -n argocd \
        --type merge -p '{"operation":{"initiatedBy":{"username":"ops"},"sync":{"revision":"HEAD"}}}'
    done
  else
    log "アプリケーション ${app} を同期..."
    kubectl patch application "${app}" -n argocd \
      --type merge -p '{"operation":{"initiatedBy":{"username":"ops"},"sync":{"revision":"HEAD"}}}'
  fi
}

# ---------------------------------------------------------------------------
# コマンド: karpenter-status - Karpenter 状態確認
# ---------------------------------------------------------------------------
cmd_karpenter_status() {
  log "=== Karpenter 状態確認 ==="
  echo "--- NodePool ---"
  kubectl get nodepools -o wide
  echo ""
  echo "--- NodeClaim ---"
  kubectl get nodeclaims 2>/dev/null || true
  echo ""
  echo "--- EC2NodeClass ---"
  kubectl get ec2nodeclasses 2>/dev/null || true
  echo ""
  echo "--- Karpenter Pod ログ (最新20行) ---"
  kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter --tail=20 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# コマンド: ecr-login - ECR ログイン
# ---------------------------------------------------------------------------
cmd_ecr_login() {
  log "ECR ログイン..."
  aws ecr get-login-password --region "${AWS_REGION}" | \
    docker login --username AWS --password-stdin \
    "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
  log "ECR ログイン成功"
}

# ---------------------------------------------------------------------------
# コマンド: rds-connect - RDS 接続テスト
# ---------------------------------------------------------------------------
cmd_rds_connect() {
  local RDS_PROXY_ENDPOINT
  RDS_PROXY_ENDPOINT=$(aws cloudformation describe-stacks \
    --stack-name "${CLUSTER_NAME}-storage" \
    --query 'Stacks[0].Outputs[?OutputKey==`RdsProxyEndpoint`].OutputValue' \
    --output text)
  log "RDS Proxy接続テスト: ${RDS_PROXY_ENDPOINT}"
  # psql が必要 (踏み台EC2にインストール済み想定)
  PGPASSWORD=$(aws secretsmanager get-secret-value \
    --secret-id "${CLUSTER_NAME}/rds/password" \
    --query 'SecretString' --output text | python3 -c \
    "import sys,json; d=json.load(sys.stdin); print(d['password'])") \
  psql -h "${RDS_PROXY_ENDPOINT}" -U postgres -d appdb -c '\l'
}

# ---------------------------------------------------------------------------
# コマンド: codebuild-trigger - CodeBuild 手動実行
# ---------------------------------------------------------------------------
cmd_codebuild_trigger() {
  local project="${1:-${CLUSTER_NAME}-app-build}"
  log "CodeBuild 手動実行: ${project}"
  local build_id
  build_id=$(aws codebuild start-build \
    --project-name "${project}" \
    --query 'build.id' --output text)
  log "Build ID: ${build_id}"
  log "ビルドログ:"
  aws codebuild batch-get-builds --ids "${build_id}" \
    --query 'builds[0].logs.cloudWatchLogsArn' --output text
}

# ---------------------------------------------------------------------------
# コマンド: rotate-secrets - Secrets Manager 手動ローテーション
# ---------------------------------------------------------------------------
cmd_rotate_secrets() {
  log "Secrets ローテーション開始..."
  aws secretsmanager rotate-secret \
    --secret-id "${CLUSTER_NAME}/rds/password" \
    --rotate-immediately 2>/dev/null || \
    warn "RDS Secret ローテーション設定がありません"
}

# ---------------------------------------------------------------------------
# コマンド: helm-diff - Helm diff (デプロイ前確認)
# ---------------------------------------------------------------------------
cmd_helm_diff() {
  local chart="${1:-rails-app}"
  local ns="${2:-app}"
  log "Helm diff: ${chart} (namespace: ${ns})"
  helm diff upgrade "${chart}" \
    "s3://${AWS_ACCOUNT_ID}-helm-charts-${AWS_REGION}/charts/${chart}" \
    -n "${ns}" \
    -f "gitops/apps/${chart}/values.yaml" 2>/dev/null || \
  warn "helm-diff プラグインが必要です: helm plugin install https://github.com/databus23/helm-diff"
}

# ---------------------------------------------------------------------------
# コマンド: port-forward - ArgoCD UI ポートフォワード
# ---------------------------------------------------------------------------
cmd_port_forward_argocd() {
  log "ArgoCD UI ポートフォワード (http://localhost:8080)"
  kubectl port-forward svc/argocd-server -n argocd 8080:80
}

# ---------------------------------------------------------------------------
# メイン
# ---------------------------------------------------------------------------
setup_kubeconfig 2>/dev/null || true

case "${1:-help}" in
  status)             cmd_status ;;
  logs)               cmd_logs "${2:-app}" "${3:-rails-app}" ;;
  argocd-sync)        cmd_argocd_sync "${2:-}" ;;
  karpenter-status)   cmd_karpenter_status ;;
  ecr-login)          cmd_ecr_login ;;
  rds-connect)        cmd_rds_connect ;;
  codebuild-trigger)  cmd_codebuild_trigger "${2:-}" ;;
  rotate-secrets)     cmd_rotate_secrets ;;
  helm-diff)          cmd_helm_diff "${2:-rails-app}" "${3:-app}" ;;
  port-forward-argocd) cmd_port_forward_argocd ;;
  help|*)
    echo "使い方: $0 <command>"
    echo ""
    echo "コマンド一覧:"
    echo "  status               クラスタ全体の状態確認"
    echo "  logs [ns] [app]      Pod ログ確認"
    echo "  argocd-sync [app]    ArgoCD 手動同期"
    echo "  karpenter-status     Karpenter 状態確認"
    echo "  ecr-login            ECR ログイン"
    echo "  rds-connect          RDS 接続テスト"
    echo "  codebuild-trigger [project]  CodeBuild 手動実行"
    echo "  rotate-secrets       Secrets ローテーション"
    echo "  helm-diff [chart] [ns]  Helm diff確認"
    echo "  port-forward-argocd  ArgoCD UI ポートフォワード"
    ;;
esac
