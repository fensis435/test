#!/usr/bin/env bash
# =============================================================================
# EKS Full-Stack Deployment Script  v4
# 2AZ構成 / System MNG (初期1台) + Karpenter worker分離 / 全Pod Identity登録
# =============================================================================
set -euo pipefail
IFS=$'\n\t'

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

log()    { echo -e "${GREEN}[$(date '+%H:%M:%S')] ✓ $*${NC}"; }
info()   { echo -e "${BLUE}[$(date '+%H:%M:%S')] ℹ $*${NC}"; }
warn()   { echo -e "${YELLOW}[$(date '+%H:%M:%S')] ⚠ $*${NC}"; }
error()  { echo -e "${RED}[$(date '+%H:%M:%S')] ✗ $*${NC}" >&2; }
header() { echo -e "\n${CYAN}══════════════════════════════════════════\n  $*\n══════════════════════════════════════════${NC}"; }

# ── 設定 ──────────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CFN_DIR="${SCRIPT_DIR}/../cfn"
ARGOCD_DIR="${SCRIPT_DIR}/../argocd"

PROJECT_NAME="${PROJECT_NAME:-eks-project}"
ENVIRONMENT="${ENVIRONMENT:-prod}"
AWS_REGION="${AWS_REGION:-ap-northeast-1}"
DOMAIN_NAME="${DOMAIN_NAME:-}"
HOSTED_ZONE_ID="${HOSTED_ZONE_ID:-}"
ARGOCD_REPO_URL="${ARGOCD_REPO_URL:-}"
ARGOCD_REPO_PATH="${ARGOCD_REPO_PATH:-apps}"
ALERT_EMAIL="${ALERT_EMAIL:-}"
GITHUB_OWNER="${GITHUB_OWNER:-}"
GITHUB_REPO="${GITHUB_REPO:-}"
GITHUB_BRANCH="${GITHUB_BRANCH:-main}"
GITHUB_HELM_REPO="${GITHUB_HELM_REPO:-helm-charts}"
GITHUB_CONNECTION_ARN="${GITHUB_CONNECTION_ARN:-}"
ECR_REPO_NAME="${ECR_REPO_NAME:-rails-app}"

CLUSTER_NAME="${PROJECT_NAME}-${ENVIRONMENT}"
STACK_PREFIX="${PROJECT_NAME}-${ENVIRONMENT}"

KARPENTER_VERSION="1.0.8"
ARGOCD_VERSION="7.6.12"
ALB_CONTROLLER_VERSION="1.9.2"
METRICS_SERVER_VERSION="3.12.2"
CERT_MANAGER_VERSION="v1.16.2"
ESO_VERSION="0.10.4"

# ── ヘルパー ──────────────────────────────────────────────────────────────────
check_prerequisites() {
  header "Prerequisites チェック"
  for tool in aws kubectl helm jq curl yq; do
    command -v "$tool" &>/dev/null && log "$tool found" || { error "Missing: $tool"; exit 1; }
  done
  for var in DOMAIN_NAME HOSTED_ZONE_ID ARGOCD_REPO_URL GITHUB_OWNER GITHUB_REPO GITHUB_CONNECTION_ARN; do
    [[ -z "${!var}" ]] && { error "Required: $var"; exit 1; }
  done
  AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text --region "${AWS_REGION}")
  log "Account: ${AWS_ACCOUNT_ID}  Region: ${AWS_REGION}"
}

deploy_stack() {
  local name="$1" tmpl="$2" params="${3:-}"
  info "Stack: ${name}"
  local cmd="aws cloudformation deploy --stack-name ${name} --template-file ${tmpl} \
    --capabilities CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND \
    --region ${AWS_REGION} --no-fail-on-empty-changeset"
  [[ -n "$params" ]] && cmd+=" --parameter-overrides ${params}"
  eval "$cmd"
  log "Stack done: ${name}"
}

get_output() {
  aws cloudformation describe-stacks --stack-name "$1" --region "${AWS_REGION}" \
    --query "Stacks[0].Outputs[?OutputKey=='$2'].OutputValue" --output text
}

# Pod Identity 関連付け (冪等)
pia() {
  local ns="$1" sa="$2" role="$3"
  aws eks create-pod-identity-association \
    --cluster-name "${CLUSTER_NAME}" \
    --namespace "${ns}" --service-account "${sa}" \
    --role-arn "${role}" --region "${AWS_REGION}" 2>/dev/null \
  || aws eks update-pod-identity-association \
    --cluster-name "${CLUSTER_NAME}" \
    --namespace "${ns}" --service-account "${sa}" \
    --role-arn "${role}" --region "${AWS_REGION}" 2>/dev/null \
  || true
  info "  PodIdentity: ${ns}/${sa} → ${role##*/}"
}

# ── Phase 1: Base ─────────────────────────────────────────────────────────────
deploy_base() {
  header "Phase 1: VPC(2AZ), KMS x5, Cognito, ACM"
  deploy_stack "${STACK_PREFIX}-base" "${CFN_DIR}/01-base.yaml" \
    "ProjectName=${PROJECT_NAME} Environment=${ENVIRONMENT} DomainName=${DOMAIN_NAME} HostedZoneId=${HOSTED_ZONE_ID}"
  info "Waiting for ACM DNS validation..."
  local cert
  cert=$(get_output "${STACK_PREFIX}-base" "ACMCertificateArn")
  aws acm wait certificate-validated --certificate-arn "${cert}" --region "${AWS_REGION}" \
    || warn "ACM validation timeout — check Route53 CNAME"
}

# ── Phase 2: Security ─────────────────────────────────────────────────────────
deploy_security() {
  header "Phase 2: Security Groups & WAF"
  deploy_stack "${STACK_PREFIX}-security" "${CFN_DIR}/02-security.yaml" \
    "ProjectName=${PROJECT_NAME} Environment=${ENVIRONMENT}"
}

# ── Phase 3: IAM ──────────────────────────────────────────────────────────────
deploy_iam() {
  header "Phase 3: IAM Roles (全Pod Identity対象ロール含む)"
  deploy_stack "${STACK_PREFIX}-iam" "${CFN_DIR}/03-iam.yaml" \
    "ProjectName=${PROJECT_NAME} Environment=${ENVIRONMENT}"
}

# ── Phase 4: VPC Endpoints (2AZ) ──────────────────────────────────────────────
deploy_vpc_endpoints() {
  header "Phase 4: VPC Endpoints 2AZ (ECR/STS/SM/KMS/SQS/EKS/EFS/SSM)"
  deploy_stack "${STACK_PREFIX}-vpc-endpoints" "${CFN_DIR}/05-vpc-endpoints.yaml" \
    "ProjectName=${PROJECT_NAME} Environment=${ENVIRONMENT}"
  log "AWS API → PrivateLink経由 (NAT不要)"
}

# ── Phase 5: Observability ────────────────────────────────────────────────────
deploy_observability() {
  header "Phase 5: CloudWatch LogGroups/Alarms/Dashboard + Secrets Manager"
  local params="ProjectName=${PROJECT_NAME} Environment=${ENVIRONMENT}"
  [[ -n "${ALERT_EMAIL}" ]] && params+=" AlertEmail=${ALERT_EMAIL}"
  deploy_stack "${STACK_PREFIX}-observability" "${CFN_DIR}/06-observability.yaml" "${params}"

  # Cognito設定シークレット更新
  local pool client secret_arn
  pool=$(get_output    "${STACK_PREFIX}-base"         "CognitoUserPoolId")
  client=$(get_output  "${STACK_PREFIX}-base"         "CognitoUserPoolClientId")
  secret_arn=$(get_output "${STACK_PREFIX}-observability" "CognitoConfigSecretArn" 2>/dev/null || echo "")
  if [[ -n "${secret_arn}" ]]; then
    aws secretsmanager put-secret-value \
      --secret-id "${secret_arn}" \
      --secret-string "$(jq -n \
        --arg p "${pool}" --arg c "${client}" --arg r "${AWS_REGION}" \
        --arg i "https://cognito-idp.${AWS_REGION}.amazonaws.com/${pool}" \
        '{user_pool_id:$p,client_id:$c,client_secret:"SET_MANUALLY",region:$r,jwt_issuer:$i}')" \
      --region "${AWS_REGION}" 2>/dev/null || true
    log "Cognito config secret updated"
  fi
}

# ── Phase 6: Cognito Pipeline + ECR + CodeBuild ───────────────────────────────
deploy_cognito_pipeline() {
  header "Phase 6: CloudTrail→EventBridge→SQS, ECR, CodeBuild, CodePipeline"
  deploy_stack "${STACK_PREFIX}-cognito-pipeline" "${CFN_DIR}/07-cognito-pipeline-ecr-codebuild.yaml" \
    "ProjectName=${PROJECT_NAME} Environment=${ENVIRONMENT} \
     GitHubOwner=${GITHUB_OWNER} GitHubRepo=${GITHUB_REPO} \
     GitHubBranch=${GITHUB_BRANCH} GitHubHelmRepo=${GITHUB_HELM_REPO} \
     GitHubConnectionArn=${GITHUB_CONNECTION_ARN} ECRRepositoryName=${ECR_REPO_NAME}"
  warn "GitHub PAT を手動設定: ${PROJECT_NAME}/${ENVIRONMENT}/github/token"
}

# ── Phase 7: EKS + EFS + RDS ─────────────────────────────────────────────────
deploy_eks_rds_efs() {
  header "Phase 7: EKS(2AZ) + System MNG(初期1台) + EFS + RDS Aurora"
  deploy_stack "${STACK_PREFIX}-eks-rds-efs" "${CFN_DIR}/04-eks-rds-efs.yaml" \
    "ProjectName=${PROJECT_NAME} Environment=${ENVIRONMENT}"

  info "kubeconfig更新..."
  aws eks update-kubeconfig --name "${CLUSTER_NAME}" --region "${AWS_REGION}" --alias "${CLUSTER_NAME}"
  aws eks wait cluster-active --name "${CLUSTER_NAME}" --region "${AWS_REGION}"

  info "System MNG node ready待機 (最大5分)..."
  kubectl wait node --selector=role=system --for=condition=Ready --timeout=300s || warn "Node wait timeout"
  log "EKS cluster active: ${CLUSTER_NAME}"

  info "System MNG: 初期1台 (性能不足時は手動でDesiredSize=2に変更)"
  info "  aws eks update-nodegroup-config --cluster-name ${CLUSTER_NAME} --nodegroup-name ${CLUSTER_NAME}-system --scaling-config desiredSize=2"
}

# ── Phase 8: Helm repos ───────────────────────────────────────────────────────
setup_helm_repos() {
  header "Phase 8: Helm Repositories"
  helm repo add karpenter         https://charts.karpenter.sh
  helm repo add aws-load-balancer https://aws.github.io/eks-charts
  helm repo add argo              https://argoproj.github.io/argo-helm
  helm repo add metrics-server    https://kubernetes-sigs.github.io/metrics-server
  helm repo add external-secrets  https://charts.external-secrets.io
  helm repo add jetstack          https://charts.jetstack.io
  helm repo update
  log "Helm repos configured"
}

# ── Phase 9: Karpenter ───────────────────────────────────────────────────────
# Karpenter自体はsystem MNG上で動く (CriticalAddonsOnly toleration持つ)
# Karpenterが起動するEC2はワークロード用NodePool — system MNGとは完全分離
deploy_karpenter() {
  header "Phase 9: Karpenter (workload EC2 auto-scale)"

  local role_arn queue_name node_role ebs_key
  role_arn=$(get_output   "${STACK_PREFIX}-iam" "KarpenterControllerRoleArn")
  queue_name=$(get_output "${STACK_PREFIX}-iam" "KarpenterInterruptionQueueName")
  node_role=$(get_output  "${STACK_PREFIX}-iam" "EKSNodeRoleArn")
  ebs_key=$(get_output    "${STACK_PREFIX}-base" "EBSKMSKeyArn")

  kubectl create namespace karpenter --dry-run=client -o yaml | kubectl apply -f -

  # Pod Identity (karpenter controller)
  pia "karpenter" "karpenter" "${role_arn}"

  # Karpenter helm: system MNG上で動くようにtoleration + nodeSelector設定
  helm upgrade --install karpenter karpenter/karpenter \
    --namespace karpenter --version "${KARPENTER_VERSION}" \
    --set "settings.clusterName=${CLUSTER_NAME}" \
    --set "settings.interruptionQueue=${queue_name}" \
    --set "serviceAccount.name=karpenter" \
    --set controller.resources.requests.cpu=250m \
    --set controller.resources.requests.memory=512Mi \
    --set controller.resources.limits.cpu=1 \
    --set controller.resources.limits.memory=1Gi \
    --set replicas=1 \
    --set "nodeSelector.role=system" \
    --set "tolerations[0].key=CriticalAddonsOnly" \
    --set "tolerations[0].operator=Exists" \
    --set "tolerations[0].effect=NoSchedule" \
    --wait --timeout 5m

  log "Karpenter controller deployed on system MNG"

  # ── EC2NodeClass & NodePool (workload専用) ─────────────────────────────────
  local node_role_name="${node_role##*/}"
  cat <<EOF | kubectl apply -f -
# Karpenterが起動するEC2の設定 (system MNGとは独立)
apiVersion: karpenter.k8s.aws/v1
kind: EC2NodeClass
metadata:
  name: workload
spec:
  amiFamily: AL2023
  role: "${node_role_name}"
  subnetSelectorTerms:
    - tags:
        karpenter.sh/discovery: "${CLUSTER_NAME}"
  securityGroupSelectorTerms:
    - tags:
        karpenter.sh/discovery: "${CLUSTER_NAME}"
  blockDeviceMappings:
    - deviceName: /dev/xvda
      ebs:
        volumeSize: 100Gi
        volumeType: gp3
        encrypted: true
        kmsKeyID: "${ebs_key}"
        deleteOnTermination: true
        throughput: 200
        iops: 3000
  metadataOptions:
    httpTokens: required
    httpPutResponseHopLimit: 1
  tags:
    Project: "${PROJECT_NAME}"
    Environment: "${ENVIRONMENT}"
    ManagedBy: karpenter
    NodeType: workload
---
# デフォルトワークロード用NodePool (Railsアプリ、計算Job等)
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: workload
spec:
  template:
    metadata:
      labels:
        role: workload
        node-type: karpenter
    spec:
      nodeClassRef:
        group: karpenter.k8s.aws
        kind: EC2NodeClass
        name: workload
      requirements:
        - key: karpenter.k8s.aws/instance-category
          operator: In
          values: [m, c, r]
        - key: karpenter.k8s.aws/instance-generation
          operator: Gt
          values: ["5"]
        - key: kubernetes.io/arch
          operator: In
          values: [amd64]
        - key: karpenter.sh/capacity-type
          operator: In
          values: [spot, on-demand]
        - key: karpenter.k8s.aws/instance-size
          operator: NotIn
          values: [nano, micro, small, medium, metal]
        # system MNGとの混在防止: CriticalAddonsOnly taintなし
      expireAfter: 720h
      terminationGracePeriod: 48h
  limits:
    cpu: "200"
    memory: 800Gi
  disruption:
    consolidationPolicy: WhenEmptyOrUnderutilized
    consolidateAfter: 1m
---
# 計算集約型Job用NodePool (多量Pod生成時に使用)
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: compute
spec:
  template:
    metadata:
      labels:
        role: compute
        node-type: karpenter
    spec:
      nodeClassRef:
        group: karpenter.k8s.aws
        kind: EC2NodeClass
        name: workload
      requirements:
        - key: karpenter.k8s.aws/instance-category
          operator: In
          values: [c]   # compute optimized
        - key: karpenter.k8s.aws/instance-generation
          operator: Gt
          values: ["5"]
        - key: karpenter.sh/capacity-type
          operator: In
          values: [spot]   # 計算Jobはspot優先
      taints:
        - key: workload-type
          value: compute
          effect: NoSchedule
      expireAfter: 2h   # 短命
      terminationGracePeriod: 10m
  limits:
    cpu: "500"
    memory: 2000Gi
  disruption:
    consolidationPolicy: WhenEmpty
    consolidateAfter: 30s
EOF
  log "EC2NodeClass + NodePool(workload/compute) applied"
}

# ── Phase 10: ALB Controller ──────────────────────────────────────────────────
deploy_alb_controller() {
  header "Phase 10: AWS Load Balancer Controller"
  local role_arn vpc_id
  role_arn=$(get_output "${STACK_PREFIX}-iam" "ALBControllerRoleArn")
  vpc_id=$(get_output   "${STACK_PREFIX}-base" "VpcId")

  kubectl create namespace aws-load-balancer --dry-run=client -o yaml | kubectl apply -f -
  pia "aws-load-balancer" "aws-load-balancer-controller" "${role_arn}"

  helm upgrade --install aws-load-balancer-controller \
    aws-load-balancer-controller/aws-load-balancer-controller \
    --namespace aws-load-balancer --version "${ALB_CONTROLLER_VERSION}" \
    --set clusterName="${CLUSTER_NAME}" \
    --set serviceAccount.name=aws-load-balancer-controller \
    --set region="${AWS_REGION}" --set vpcId="${vpc_id}" \
    --set replicaCount=1 \
    --set "nodeSelector.role=system" \
    --set "tolerations[0].key=CriticalAddonsOnly" \
    --set "tolerations[0].operator=Exists" \
    --set "tolerations[0].effect=NoSchedule" \
    --wait --timeout 5m
  log "ALB Controller on system MNG"
}

# ── Phase 11: Storage Classes ─────────────────────────────────────────────────
deploy_storage_classes() {
  header "Phase 11: EBS/EFS StorageClass"
  local ebs_key efs_id
  ebs_key=$(get_output "${STACK_PREFIX}-base" "EBSKMSKeyArn")
  efs_id=$(get_output  "${STACK_PREFIX}-eks-rds-efs" "EFSFileSystemId")

  cat <<EOF | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ebs-gp3-encrypted
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: ebs.csi.aws.com
volumeBindingMode: WaitForFirstConsumer
reclaimPolicy: Retain
allowVolumeExpansion: true
parameters:
  type: gp3
  encrypted: "true"
  kmsKeyId: "${ebs_key}"
---
# EFS: ReadWriteMany — Railsサーバ用 (2AZ間でPVを共有、AZ障害でもPending不発生)
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: efs-sc
provisioner: efs.csi.aws.com
reclaimPolicy: Retain
volumeBindingMode: Immediate
parameters:
  provisioningMode: efs-ap
  fileSystemId: "${efs_id}"
  directoryPerms: "755"
  uid: "1000"
  gid: "1000"
EOF
  log "StorageClass: ebs-gp3-encrypted(default) + efs-sc"
}

# ── Phase 12: Metrics Server ──────────────────────────────────────────────────
deploy_metrics_server() {
  header "Phase 12: Metrics Server"
  helm upgrade --install metrics-server metrics-server/metrics-server \
    --namespace kube-system --version "${METRICS_SERVER_VERSION}" \
    --set replicas=1 \
    --set "tolerations[0].key=CriticalAddonsOnly" \
    --set "tolerations[0].operator=Exists" \
    --set "tolerations[0].effect=NoSchedule" \
    --set "nodeSelector.role=system" \
    --wait --timeout 3m
  log "Metrics Server on system MNG"
}

# ── Phase 13: cert-manager ────────────────────────────────────────────────────
deploy_cert_manager() {
  header "Phase 13: cert-manager (rsync SSH鍵配布)"
  helm upgrade --install cert-manager jetstack/cert-manager \
    --namespace cert-manager --create-namespace \
    --version "${CERT_MANAGER_VERSION}" \
    --set installCRDs=true \
    --set replicaCount=1 \
    --set webhook.replicaCount=1 \
    --set cainjector.replicaCount=1 \
    --set "nodeSelector.role=system" \
    --set "tolerations[0].key=CriticalAddonsOnly" \
    --set "tolerations[0].operator=Exists" \
    --set "tolerations[0].effect=NoSchedule" \
    --set "webhook.nodeSelector.role=system" \
    --set "webhook.tolerations[0].key=CriticalAddonsOnly" \
    --set "webhook.tolerations[0].operator=Exists" \
    --set "webhook.tolerations[0].effect=NoSchedule" \
    --set "cainjector.nodeSelector.role=system" \
    --set "cainjector.tolerations[0].key=CriticalAddonsOnly" \
    --set "cainjector.tolerations[0].operator=Exists" \
    --set "cainjector.tolerations[0].effect=NoSchedule" \
    --wait --timeout 5m

  kubectl wait pod -l app.kubernetes.io/instance=cert-manager \
    -n cert-manager --for=condition=Ready --timeout=120s

  # ClusterIssuers 適用
  kubectl apply -f "${ARGOCD_DIR}/cluster-issuers.yaml"

  info "Internal CA certificate 待機..."
  for i in $(seq 1 24); do
    ready=$(kubectl get certificate cluster-internal-ca -n cert-manager \
      -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "")
    [[ "${ready}" == "True" ]] && { log "cert-manager ready"; return; }
    sleep 5
  done
  warn "cert-manager CA timeout — 続行"
}

# ── Phase 14: ESO ─────────────────────────────────────────────────────────────
deploy_eso() {
  header "Phase 14: External Secrets Operator"
  local eso_role
  eso_role=$(get_output "${STACK_PREFIX}-iam" "ESOControllerRoleArn")

  kubectl create namespace external-secrets --dry-run=client -o yaml | kubectl apply -f -

  # Pod Identity: ESO controller SA → ESOControllerRole (SM呼び出し権限)
  pia "external-secrets" "external-secrets"                 "${eso_role}"
  pia "external-secrets" "external-secrets-webhook"         "${eso_role}"
  pia "external-secrets" "external-secrets-cert-controller" "${eso_role}"

  helm upgrade --install external-secrets external-secrets/external-secrets \
    --namespace external-secrets --version "${ESO_VERSION}" \
    --set installCRDs=true \
    --set replicaCount=1 \
    --set "nodeSelector.role=system" \
    --set "tolerations[0].key=CriticalAddonsOnly" \
    --set "tolerations[0].operator=Exists" \
    --set "tolerations[0].effect=NoSchedule" \
    --set "webhook.nodeSelector.role=system" \
    --set "webhook.tolerations[0].key=CriticalAddonsOnly" \
    --set "webhook.tolerations[0].operator=Exists" \
    --set "webhook.tolerations[0].effect=NoSchedule" \
    --set "certController.nodeSelector.role=system" \
    --set "certController.tolerations[0].key=CriticalAddonsOnly" \
    --set "certController.tolerations[0].operator=Exists" \
    --set "certController.tolerations[0].effect=NoSchedule" \
    --wait --timeout 5m

  log "ESO deployed on system MNG"

  # ClusterSecretStore 適用 (SM → K8s Secret の橋渡し)
  cat <<EOF | kubectl apply -f -
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: aws-secretsmanager
spec:
  provider:
    aws:
      service: SecretsManager
      region: ${AWS_REGION}
      auth:
        jwt:
          serviceAccountRef:
            name: external-secrets          # Pod IdentityのSA
            namespace: external-secrets
EOF
  log "ClusterSecretStore(aws-secretsmanager) applied"
}

# ── Phase 15: ArgoCD ──────────────────────────────────────────────────────────
deploy_argocd() {
  header "Phase 15: ArgoCD (GitOps)"
  local role cert waf alb_sg
  role=$(get_output "${STACK_PREFIX}-iam"      "ArgoCDRoleArn")
  cert=$(get_output "${STACK_PREFIX}-base"     "ACMCertificateArn")
  waf=$(get_output  "${STACK_PREFIX}-security" "WAFWebACLArn")
  alb_sg=$(get_output "${STACK_PREFIX}-security" "ALBSecurityGroupId")

  kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
  pia "argocd" "argocd-server" "${role}"

  helm upgrade --install argocd argo/argo-cd \
    --namespace argocd --version "${ARGOCD_VERSION}" \
    --values - <<HELMVALUES
global:
  domain: argocd.${DOMAIN_NAME}
server:
  replicas: 1
  # system MNG上で動く
  nodeSelector:
    role: system
  tolerations:
    - key: CriticalAddonsOnly
      operator: Exists
      effect: NoSchedule
  ingress:
    enabled: true
    ingressClassName: alb
    annotations:
      alb.ingress.kubernetes.io/scheme: internet-facing
      alb.ingress.kubernetes.io/target-type: ip
      alb.ingress.kubernetes.io/certificate-arn: "${cert}"
      alb.ingress.kubernetes.io/ssl-policy: ELBSecurityPolicy-TLS13-1-2-2021-06
      alb.ingress.kubernetes.io/wafv2-acl-arn: "${waf}"
      alb.ingress.kubernetes.io/security-groups: "${alb_sg}"
      alb.ingress.kubernetes.io/listen-ports: '[{"HTTP":80},{"HTTPS":443}]'
      alb.ingress.kubernetes.io/ssl-redirect: "443"
    hosts:
      - argocd.${DOMAIN_NAME}
repoServer:
  replicas: 1
  nodeSelector:
    role: system
  tolerations:
    - key: CriticalAddonsOnly
      operator: Exists
      effect: NoSchedule
applicationSet:
  replicas: 1
  nodeSelector:
    role: system
  tolerations:
    - key: CriticalAddonsOnly
      operator: Exists
      effect: NoSchedule
controller:
  nodeSelector:
    role: system
  tolerations:
    - key: CriticalAddonsOnly
      operator: Exists
      effect: NoSchedule
redis:
  nodeSelector:
    role: system
  tolerations:
    - key: CriticalAddonsOnly
      operator: Exists
      effect: NoSchedule
dex:
  nodeSelector:
    role: system
  tolerations:
    - key: CriticalAddonsOnly
      operator: Exists
      effect: NoSchedule
configs:
  params:
    server.insecure: true
  cm:
    url: https://argocd.${DOMAIN_NAME}
    exec.enabled: "false"
HELMVALUES

  kubectl wait pod -l app.kubernetes.io/name=argocd-server \
    -n argocd --for=condition=Ready --timeout=300s

  local pw
  pw=$(kubectl get secret argocd-initial-admin-secret \
    -n argocd -o jsonpath='{.data.password}' | base64 -d)

  aws secretsmanager put-secret-value \
    --secret-id "${PROJECT_NAME}/${ENVIRONMENT}/argocd/admin-password" \
    --secret-string "${pw}" --region "${AWS_REGION}" 2>/dev/null || \
  aws secretsmanager create-secret \
    --name "${PROJECT_NAME}/${ENVIRONMENT}/argocd/admin-password" \
    --secret-string "${pw}" --region "${AWS_REGION}"

  log "ArgoCD on system MNG. Admin PW → Secrets Manager"
}

# ── Phase 16: 全Pod Identity登録 ──────────────────────────────────────────────
configure_pod_identities() {
  header "Phase 16: Pod Identity Associations (全登録)"

  # IAMロール取得
  local karpenter_role alb_role eso_role argocd_role cw_role fb_role rails_role bridge_role ebs_role efs_role
  karpenter_role=$(get_output "${STACK_PREFIX}-iam" "KarpenterControllerRoleArn")
  alb_role=$(     get_output  "${STACK_PREFIX}-iam" "ALBControllerRoleArn")
  eso_role=$(     get_output  "${STACK_PREFIX}-iam" "ESOControllerRoleArn")
  argocd_role=$(  get_output  "${STACK_PREFIX}-iam" "ArgoCDRoleArn")
  cw_role=$(      get_output  "${STACK_PREFIX}-iam" "CloudWatchAgentRoleArn")
  fb_role=$(      get_output  "${STACK_PREFIX}-iam" "FluentBitRoleArn")
  rails_role=$(   get_output  "${STACK_PREFIX}-iam" "RailsPodRoleArn")
  bridge_role=$(  get_output  "${STACK_PREFIX}-iam" "ArgoCDBridgeRoleArn")
  ebs_role=$(     get_output  "${STACK_PREFIX}-iam" "EBSCSIDriverRoleArn")
  efs_role=$(     get_output  "${STACK_PREFIX}-iam" "EFSCSIDriverRoleArn")

  info "=== 管理系 Pod (system MNG上) ==="
  # Karpenter
  pia "karpenter"         "karpenter"                         "${karpenter_role}"
  # ALB Controller
  pia "aws-load-balancer" "aws-load-balancer-controller"      "${alb_role}"
  # ESO: controller + webhook + cert-controller の3SA全部
  pia "external-secrets"  "external-secrets"                  "${eso_role}"
  pia "external-secrets"  "external-secrets-webhook"          "${eso_role}"
  pia "external-secrets"  "external-secrets-cert-controller"  "${eso_role}"
  # ArgoCD: server + application-controller (applicationset-controller はargocd-roleを共用)
  pia "argocd"            "argocd-server"                     "${argocd_role}"
  pia "argocd"            "argocd-application-controller"     "${argocd_role}"
  pia "argocd"            "argocd-applicationset-controller"  "${argocd_role}"
  # CloudWatch Agent + Fluent Bit (amazon-cloudwatch-observability addon が使う)
  kubectl create namespace amazon-cloudwatch --dry-run=client -o yaml | kubectl apply -f -
  pia "amazon-cloudwatch" "cloudwatch-agent"                  "${cw_role}"
  pia "amazon-cloudwatch" "fluent-bit"                        "${fb_role}"
  pia "amazon-cloudwatch" "amazon-cloudwatch-observability"   "${cw_role}"
  # EBS/EFS CSI (kube-system)
  pia "kube-system"       "ebs-csi-controller-sa"             "${ebs_role}"
  pia "kube-system"       "efs-csi-controller-sa"             "${efs_role}"

  info "=== Rails系 Pod (Karpenter workload nodes上) ==="
  # Rails サーバ用 (gui/app namespace の rails-*-sa)
  # ※ 新namespace作成時は deploy_rails_namespace() で追加
  kubectl create namespace rails-system --dry-run=client -o yaml | kubectl apply -f -
  pia "rails-system"      "rails-gui-sa"                      "${rails_role}"
  pia "rails-system"      "rails-app-sa"                      "${rails_role}"
  # ArgoCD Bridge (Rails JobがArgoCD APIを呼ぶ用)
  pia "rails-system"      "rails-bridge-sa"                   "${bridge_role}"

  log "全Pod Identity登録完了"
}

# ── Phase 17: Container Insights ──────────────────────────────────────────────
install_container_insights() {
  header "Phase 17: CloudWatch Container Insights (CloudWatch Agent + Fluent Bit)"
  local cw_role
  cw_role=$(get_output "${STACK_PREFIX}-iam" "CloudWatchAgentRoleArn" 2>/dev/null || echo "")
  [[ -z "${cw_role}" ]] && { warn "CloudWatchAgentRoleArn not found — skip"; return; }

  # amazon-cloudwatch-observability addon (CWAgent + Fluent Bit を含む)
  aws eks create-addon \
    --cluster-name "${CLUSTER_NAME}" \
    --addon-name amazon-cloudwatch-observability \
    --region "${AWS_REGION}" 2>/dev/null || true

  info "CloudWatch addon 待機..."
  for i in $(seq 1 24); do
    status=$(aws eks describe-addon \
      --cluster-name "${CLUSTER_NAME}" \
      --addon-name amazon-cloudwatch-observability \
      --region "${AWS_REGION}" \
      --query "addon.status" --output text 2>/dev/null || echo "UNKNOWN")
    [[ "${status}" == "ACTIVE" ]] && { log "Container Insights ACTIVE"; return; }
    [[ "${status}" == *FAILED* ]] && { warn "Addon ${status}"; return; }
    sleep 15
  done
  warn "Container Insights timeout — 続行"
}

# ── Phase 18: ArgoCD Rails設定 ────────────────────────────────────────────────
configure_argocd_rails() {
  header "Phase 18: ArgoCD Rails AppProject + Helm Repo + Deployer Token"

  # cluster-config ConfigMap (全namespaceで参照)
  local rds_ep rds_reader pool_id client_id efs_id db_secret sqs_url ecr_uri
  rds_ep=$(get_output    "${STACK_PREFIX}-eks-rds-efs"     "RDSClusterEndpoint")
  rds_reader=$(get_output "${STACK_PREFIX}-eks-rds-efs"    "RDSClusterReaderEndpoint")
  pool_id=$(get_output   "${STACK_PREFIX}-base"            "CognitoUserPoolId")
  client_id=$(get_output "${STACK_PREFIX}-base"            "CognitoUserPoolClientId")
  efs_id=$(get_output    "${STACK_PREFIX}-eks-rds-efs"     "EFSFileSystemId")
  db_secret=$(get_output "${STACK_PREFIX}-eks-rds-efs"     "RDSMasterSecretArn")
  sqs_url=$(get_output   "${STACK_PREFIX}-cognito-pipeline" "CognitoEventQueueUrl")
  ecr_uri=$(get_output   "${STACK_PREFIX}-cognito-pipeline" "ECRRepositoryUri")

  cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: cluster-config
  namespace: argocd
data:
  PROJECT_NAME:           "${PROJECT_NAME}"
  ENVIRONMENT:            "${ENVIRONMENT}"
  AWS_REGION:             "${AWS_REGION}"
  AWS_ACCOUNT_ID:         "${AWS_ACCOUNT_ID}"
  DOMAIN_NAME:            "${DOMAIN_NAME}"
  CLUSTER_NAME:           "${CLUSTER_NAME}"
  RDS_ENDPOINT:           "${rds_ep}"
  RDS_READER_ENDPOINT:    "${rds_reader}"
  COGNITO_USER_POOL_ID:   "${pool_id}"
  COGNITO_CLIENT_ID:      "${client_id}"
  EFS_FILE_SYSTEM_ID:     "${efs_id}"
  DB_SECRET_ARN:          "${db_secret}"
  COGNITO_SQS_QUEUE_URL:  "${sqs_url}"
  ECR_REPOSITORY_URI:     "${ecr_uri}"
  HELM_REPO_URL:          "https://${GITHUB_OWNER}.github.io/${GITHUB_HELM_REPO}"
  ARGOCD_SERVER:          "argocd-server.argocd.svc.cluster.local:443"
  ARGOCD_TOKEN_SECRET_ARN: "arn:aws:secretsmanager:${AWS_REGION}:${AWS_ACCOUNT_ID}:secret:${PROJECT_NAME}/${ENVIRONMENT}/argocd/rails-deployer-token"
EOF

  # Rails workload AppProject + Helm repo secret
  sed "s|HELM_REPO_URL_PLACEHOLDER|https://${GITHUB_OWNER}.github.io/${GITHUB_HELM_REPO}|g" \
    "${ARGOCD_DIR}/rails-apps.yaml" | kubectl apply -f -

  # Platform apps (ESO/cert-manager/cluster-issuers)
  sed "s|ARGOCD_REPO_URL_PLACEHOLDER|${ARGOCD_REPO_URL}|g" \
    "${ARGOCD_DIR}/platform-apps.yaml" | kubectl apply -f -

  # ArgoCD rails-deployer API token 生成
  info "ArgoCD rails-deployer token 生成..."
  local argocd_pw token=""
  argocd_pw=$(aws secretsmanager get-secret-value \
    --secret-id "${PROJECT_NAME}/${ENVIRONMENT}/argocd/admin-password" \
    --query SecretString --output text --region "${AWS_REGION}")

  local argocd_jwt
  argocd_jwt=$(curl -sk "https://argocd.${DOMAIN_NAME}/api/v1/session" \
    -d "{\"username\":\"admin\",\"password\":\"${argocd_pw}\"}" \
    | jq -r '.token // empty' 2>/dev/null || echo "")

  if [[ -n "${argocd_jwt}" ]]; then
    token=$(curl -sk -X POST \
      "https://argocd.${DOMAIN_NAME}/api/v1/account/rails-deployer/token" \
      -H "Authorization: Bearer ${argocd_jwt}" \
      | jq -r '.token // empty' 2>/dev/null || echo "")
  fi

  if [[ -n "${token}" ]]; then
    aws secretsmanager put-secret-value \
      --secret-id "${PROJECT_NAME}/${ENVIRONMENT}/argocd/rails-deployer-token" \
      --secret-string "{\"token\":\"${token}\"}" \
      --region "${AWS_REGION}" 2>/dev/null || \
    aws secretsmanager create-secret \
      --name "${PROJECT_NAME}/${ENVIRONMENT}/argocd/rails-deployer-token" \
      --secret-string "{\"token\":\"${token}\"}" \
      --region "${AWS_REGION}"
    log "ArgoCD rails-deployer token → Secrets Manager"
  else
    warn "ArgoCD token 自動生成失敗 — 手動設定:"
    warn "  argocd account generate-token --account rails-deployer"
    warn "  Secret: ${PROJECT_NAME}/${ENVIRONMENT}/argocd/rails-deployer-token"
  fi

  # App-of-Apps root
  cat <<EOF | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: root
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: ${ARGOCD_REPO_URL}
    targetRevision: HEAD
    path: ${ARGOCD_REPO_PATH}
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
    retry:
      limit: 5
      backoff: {duration: 5s, factor: 2, maxDuration: 3m}
EOF
  log "ArgoCD App-of-Apps configured"
}

# ── Phase 19: Route53 ─────────────────────────────────────────────────────────
configure_dns() {
  header "Phase 19: Route53 DNS"
  info "ALB待機 (最大5分)..."
  local retries=30 alb_dns=""
  while [[ $retries -gt 0 && -z "${alb_dns}" ]]; do
    alb_dns=$(kubectl get ingress -n argocd \
      -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
    [[ -z "${alb_dns}" ]] && { sleep 10; ((retries--)); }
  done
  if [[ -z "${alb_dns}" ]]; then
    warn "ALB not found — Route53レコードを手動作成してください"; return
  fi
  local alb_zone
  case "${AWS_REGION}" in
    ap-northeast-1) alb_zone="Z14GRHDCWA56QT" ;;
    us-east-1)      alb_zone="Z35SXDOTRQ7X7K" ;;
    us-west-2)      alb_zone="Z1H1FL5HABSF5"  ;;
    eu-west-1)      alb_zone="Z32O12XQLNTSW2" ;;
    *)              alb_zone="Z14GRHDCWA56QT" ;;
  esac
  aws route53 change-resource-record-sets \
    --hosted-zone-id "${HOSTED_ZONE_ID}" \
    --change-batch "$(jq -n \
      --arg dns "${alb_dns}" --arg zone "${alb_zone}" --arg d "${DOMAIN_NAME}" \
      '{Changes:[
        {Action:"UPSERT",ResourceRecordSet:{Name:$d,Type:"A",
          AliasTarget:{HostedZoneId:$zone,DNSName:$dns,EvaluateTargetHealth:true}}},
        {Action:"UPSERT",ResourceRecordSet:{Name:("*."+$d),Type:"A",
          AliasTarget:{HostedZoneId:$zone,DNSName:$dns,EvaluateTargetHealth:true}}}
      ]}')"
  log "Route53: *.${DOMAIN_NAME} → ${alb_dns}"
}

# ── Phase 20: 確認 ────────────────────────────────────────────────────────────
verify_deployment() {
  header "Phase 20: Verification"
  echo "=== Nodes ==="
  kubectl get nodes -o wide

  echo ""
  echo "=== System MNG Pod分布 ==="
  kubectl get pods -A -o wide \
    --field-selector spec.nodeName!="" 2>/dev/null \
    | grep -E "NAMESPACE|karpenter|argocd|external-secrets|cert-manager|aws-load-balancer|amazon-cloudwatch" \
    | head -30

  echo ""
  echo "=== NodePools (Karpenter workload) ==="
  kubectl get nodepools 2>/dev/null || true

  echo ""
  echo "=== Pod Identities ==="
  aws eks list-pod-identity-associations \
    --cluster-name "${CLUSTER_NAME}" --region "${AWS_REGION}" \
    --query "associations[].{NS:namespace,SA:serviceAccount,Role:roleArn}" \
    --output table 2>/dev/null || true

  echo ""
  echo "=== StorageClass ==="
  kubectl get storageclass

  log "Verification complete"
}

# ── Namespace準備 (Rails Jobから呼ばれるヘルパー) ─────────────────────────────
deploy_rails_namespace() {
  local ns_type="${1}"  # gui | app
  local ns_id="${2}"
  local namespace="${ns_type}-${ns_id}"
  local rails_role
  rails_role=$(get_output "${STACK_PREFIX}-iam" "RailsPodRoleArn")
  local bridge_role
  bridge_role=$(get_output "${STACK_PREFIX}-iam" "ArgoCDBridgeRoleArn")
  local sa_name="rails-${ns_type}-sa"

  info "Namespace準備: ${namespace}"
  kubectl create namespace "${namespace}" --dry-run=client -o yaml | kubectl apply -f -
  kubectl label namespace "${namespace}" \
    "app.kubernetes.io/managed-by-rails=${ns_type}" \
    "app.kubernetes.io/ns-type=${ns_type}" \
    --overwrite

  # Pod Identity: RailsのSA + BridgeSA
  pia "${namespace}" "${sa_name}"         "${rails_role}"
  pia "${namespace}" "rails-bridge-sa"    "${bridge_role}"

  # cluster-config ConfigMapを新namespaceにコピー
  kubectl get configmap cluster-config -n argocd -o json \
    | jq ".metadata.namespace=\"${namespace}\" \
      | del(.metadata.resourceVersion,.metadata.uid,.metadata.creationTimestamp,.metadata.annotations)" \
    | kubectl apply -f -

  log "Namespace ${namespace} ready"
}

# ── サマリー ──────────────────────────────────────────────────────────────────
print_summary() {
  header "🎉 Deployment Complete"
  cat <<SUMMARY
  ┌─────────────────────────────────────────────────────────────────┐
  │                    Infrastructure Summary                        │
  ├─────────────────────────────────────────────────────────────────┤
  │  Cluster:       ${CLUSTER_NAME}
  │  Region:        ${AWS_REGION} (2AZ)
  │  ArgoCD:        https://argocd.${DOMAIN_NAME}
  ├─────────────────────────────────────────────────────────────────┤
  │  Node構成:                                                      │
  │  ・System MNG: 初期1台 (CriticalAddonsOnly taint)              │
  │    → Karpenter/ArgoCD/ESO/ALB-ctrl/cert-manager/CW-Agent 等   │
  │    → 性能不足時のみ手動でDesiredSize=2                          │
  │  ・Karpenter workload NodePool: 動的オートスケール              │
  │    → Railsアプリ/計算Job (spot優先)                            │
  ├─────────────────────────────────────────────────────────────────┤
  │  次のステップ:                                                  │
  │  1. GitHub PAT: ${PROJECT_NAME}/${ENVIRONMENT}/github/token    │
  │  2. ArgoCD admin password変更                                   │
  │  3. ArgoCD rails-deployer token確認                             │
  │  4. GitOps repo にマニフェストをpush                            │
  └─────────────────────────────────────────────────────────────────┘
SUMMARY
}

# ── 削除 ──────────────────────────────────────────────────────────────────────
destroy_all() {
  warn "⚠️  全リソース削除"
  read -p "Type 'DELETE ${CLUSTER_NAME}': " confirm
  [[ "${confirm}" != "DELETE ${CLUSTER_NAME}" ]] && { info "Cancel."; exit 0; }
  for rel in argocd external-secrets cert-manager aws-load-balancer-controller karpenter metrics-server; do
    helm uninstall "${rel}" -n "${rel%%-*}" 2>/dev/null || true
  done
  for stack in eks-rds-efs cognito-pipeline observability vpc-endpoints iam security base; do
    aws cloudformation delete-stack \
      --stack-name "${STACK_PREFIX}-${stack}" --region "${AWS_REGION}" 2>/dev/null || true
    aws cloudformation wait stack-delete-complete \
      --stack-name "${STACK_PREFIX}-${stack}" --region "${AWS_REGION}" 2>/dev/null || true
    log "Deleted: ${STACK_PREFIX}-${stack}"
  done
}

# ── Main ──────────────────────────────────────────────────────────────────────
main() {
  local action="${1:-deploy}"
  case "${action}" in
    deploy)
      check_prerequisites
      deploy_base
      deploy_security
      deploy_iam
      deploy_vpc_endpoints
      deploy_observability
      deploy_cognito_pipeline
      deploy_eks_rds_efs
      setup_helm_repos
      deploy_karpenter
      deploy_alb_controller
      deploy_storage_classes
      deploy_metrics_server
      deploy_cert_manager
      deploy_eso
      deploy_argocd
      configure_pod_identities
      install_container_insights
      configure_argocd_rails
      configure_dns
      verify_deployment
      print_summary
      ;;
    destroy)              destroy_all ;;
    verify)               verify_deployment ;;
    dns)                  configure_dns ;;
    cert-manager)         deploy_cert_manager ;;
    eso)                  deploy_eso ;;
    argocd)               deploy_argocd; configure_argocd_rails ;;
    karpenter)            deploy_karpenter ;;
    vpc-endpoints)        deploy_vpc_endpoints ;;
    observability)        deploy_observability ;;
    cognito-pipeline)     deploy_cognito_pipeline ;;
    pod-identities)       configure_pod_identities ;;
    container-insights)   install_container_insights ;;
    # Rails Jobから呼ぶ
    rails-namespace)      deploy_rails_namespace "${2:-gui}" "${3:-default}" ;;
    *)
      echo "Usage: $0 {deploy|destroy|verify|dns|cert-manager|eso|argocd|karpenter|"
      echo "          vpc-endpoints|observability|cognito-pipeline|pod-identities|"
      echo "          container-insights|rails-namespace <gui|app> <id>}"
      echo ""
      echo "Required env vars:"
      echo "  PROJECT_NAME, ENVIRONMENT, AWS_REGION"
      echo "  DOMAIN_NAME, HOSTED_ZONE_ID, ARGOCD_REPO_URL"
      echo "  GITHUB_OWNER, GITHUB_REPO, GITHUB_CONNECTION_ARN"
      exit 1
      ;;
  esac
}

main "$@"
