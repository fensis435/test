#!/usr/bin/env bash
# =============================================================================
# destroy.sh - EKS クラスタ全リソース削除スクリプト
# 警告: 本番データが消えます。必ずバックアップ後に実行してください。
# =============================================================================
set -euo pipefail

source "$(dirname "$0")/deploy.sh" 2>/dev/null || true

CLUSTER_NAME="${CLUSTER_NAME:-private-eks-cluster}"
AWS_REGION="${AWS_REGION:-ap-northeast-1}"

log()  { echo -e "\033[1;31m[DESTROY]\033[0m $*"; }
warn() { echo -e "\033[1;33m[WARN]\033[0m    $*"; }

confirm() {
  read -rp "本当に削除しますか? クラスタ名を入力してください [${CLUSTER_NAME}]: " input
  if [ "${input}" != "${CLUSTER_NAME}" ]; then
    echo "中止しました。"
    exit 1
  fi
}

# ---------------------------------------------------------------------------
# Helm アドオン削除
# ---------------------------------------------------------------------------
delete_helm_addons() {
  log "Helm アドオン削除..."
  aws eks update-kubeconfig --name "${CLUSTER_NAME}" --region "${AWS_REGION}" 2>/dev/null || true

  for release in argocd aws-load-balancer-controller karpenter \
                 aws-efs-csi-driver aws-ebs-csi-driver external-secrets \
                 metrics-server; do
    for ns in argocd kube-system karpenter external-secrets; do
      helm uninstall "${release}" -n "${ns}" 2>/dev/null || true
    done
  done

  # Karpenter NodePool & EC2NodeClass 削除 (先にノードをドレイン)
  kubectl delete nodepools --all 2>/dev/null || true
  kubectl delete ec2nodeclasses --all 2>/dev/null || true

  # Karpenter が起動したノードの削除を待機
  log "Karpenter ノードのドレイン待機 (最大5分)..."
  for i in $(seq 1 30); do
    node_count=$(kubectl get nodes -l node-type=karpenter \
      --no-headers 2>/dev/null | wc -l || echo "0")
    [ "${node_count}" -eq 0 ] && break
    echo "  残ノード: ${node_count} (${i}/30)..."
    sleep 10
  done
}

# ---------------------------------------------------------------------------
# EKS アドオン削除
# ---------------------------------------------------------------------------
delete_eks_addons() {
  log "EKS マネージドアドオン削除..."
  for addon in amazon-cloudwatch-observability aws-ebs-csi-driver \
               aws-efs-csi-driver coredns kube-proxy vpc-cni \
               eks-pod-identity-agent; do
    aws eks delete-addon \
      --cluster-name "${CLUSTER_NAME}" \
      --addon-name "${addon}" \
      --preserve 2>/dev/null || true
  done
}

# ---------------------------------------------------------------------------
# CFn スタック削除 (逆順)
# ---------------------------------------------------------------------------
delete_stacks() {
  log "CloudFormation スタック削除..."
  local stacks=(
    "${CLUSTER_NAME}-irsa"
    "${CLUSTER_NAME}-codebuild"
    "${CLUSTER_NAME}-eks"
    "${CLUSTER_NAME}-messaging"
    "${CLUSTER_NAME}-storage"
    "${CLUSTER_NAME}-ecr"
    "${CLUSTER_NAME}-iam"
    "${CLUSTER_NAME}-network"
    "${CLUSTER_NAME}-kms"
  )

  for stack in "${stacks[@]}"; do
    log "スタック削除: ${stack}"
    aws cloudformation delete-stack --stack-name "${stack}" 2>/dev/null || true
    aws cloudformation wait stack-delete-complete \
      --stack-name "${stack}" 2>/dev/null || true
  done
}

main() {
  log "============================================"
  log "EKS クラスタ 全リソース削除"
  log "クラスタ: ${CLUSTER_NAME}"
  log "============================================"
  warn "この操作は元に戻せません！"
  confirm

  delete_helm_addons
  delete_eks_addons
  delete_stacks

  log "削除完了"
}

main "$@"
