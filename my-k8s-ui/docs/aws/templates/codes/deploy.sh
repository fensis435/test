#!/usr/bin/env bash
# =============================================================================
# EKS Full-Stack Deployment Script  (v3 — Rails + Cognito pipeline edition)
# =============================================================================
set -euo pipefail
IFS=$'\n\t'

# ── Color output ─────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

log()    { echo -e "${GREEN}[$(date '+%H:%M:%S')] ✓ $*${NC}"; }
info()   { echo -e "${BLUE}[$(date '+%H:%M:%S')] ℹ $*${NC}"; }
warn()   { echo -e "${YELLOW}[$(date '+%H:%M:%S')] ⚠ $*${NC}"; }
error()  { echo -e "${RED}[$(date '+%H:%M:%S')] ✗ $*${NC}" >&2; }
header() { echo -e "\n${CYAN}══════════════════════════════════════════\n  $*\n══════════════════════════════════════════${NC}"; }

# ── Configuration ─────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CFN_DIR="${SCRIPT_DIR}/../cfn"
HELM_DIR="${SCRIPT_DIR}/../helm"
ARGOCD_DIR="${SCRIPT_DIR}/../argocd"

# Required env vars
PROJECT_NAME="${PROJECT_NAME:-eks-project}"
ENVIRONMENT="${ENVIRONMENT:-prod}"
AWS_REGION="${AWS_REGION:-ap-northeast-1}"
DOMAIN_NAME="${DOMAIN_NAME:-}"
HOSTED_ZONE_ID="${HOSTED_ZONE_ID:-}"
ARGOCD_REPO_URL="${ARGOCD_REPO_URL:-}"
ARGOCD_REPO_PATH="${ARGOCD_REPO_PATH:-apps}"
ALERT_EMAIL="${ALERT_EMAIL:-}"

# New v3 variables
GITHUB_OWNER="${GITHUB_OWNER:-}"
GITHUB_REPO="${GITHUB_REPO:-}"
GITHUB_BRANCH="${GITHUB_BRANCH:-main}"
GITHUB_HELM_REPO="${GITHUB_HELM_REPO:-helm-charts}"
GITHUB_CONNECTION_ARN="${GITHUB_CONNECTION_ARN:-}"   # CodeStar Connection (pre-created in console)
ECR_REPO_NAME="${ECR_REPO_NAME:-rails-app}"

# Derived
CLUSTER_NAME="${PROJECT_NAME}-${ENVIRONMENT}"
STACK_PREFIX="${PROJECT_NAME}-${ENVIRONMENT}"

# Tool versions
KARPENTER_VERSION="1.0.8"
ARGOCD_VERSION="7.6.12"
ALB_CONTROLLER_VERSION="1.9.2"
METRICS_SERVER_VERSION="3.12.2"
CERT_MANAGER_VERSION="v1.16.2"

# ── Prerequisites check ───────────────────────────────────────────────────────
check_prerequisites() {
  header "Checking Prerequisites"
  local missing=()
  for tool in aws kubectl helm jq curl yq; do
    if command -v "$tool" &>/dev/null; then
      log "$tool found"
    else
      missing+=("$tool")
      error "Missing: $tool"
    fi
  done
  [[ ${#missing[@]} -gt 0 ]] && { error "Install: ${missing[*]}"; exit 1; }

  local v3_required=("DOMAIN_NAME" "HOSTED_ZONE_ID" "ARGOCD_REPO_URL"
                     "GITHUB_OWNER" "GITHUB_REPO" "GITHUB_CONNECTION_ARN")
  for var in "${v3_required[@]}"; do
    [[ -z "${!var}" ]] && { error "Required variable not set: $var"; exit 1; }
  done

  AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text --region "${AWS_REGION}")
  log "AWS Account: ${AWS_ACCOUNT_ID}, Region: ${AWS_REGION}"
}

# ── CloudFormation helpers ────────────────────────────────────────────────────
deploy_stack() {
  local stack_name="$1" template_file="$2" parameters="${3:-}"
  info "Deploying stack: ${stack_name}"
  local cmd="aws cloudformation deploy \
    --stack-name ${stack_name} \
    --template-file ${template_file} \
    --capabilities CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND \
    --region ${AWS_REGION} \
    --no-fail-on-empty-changeset"
  [[ -n "$parameters" ]] && cmd+=" --parameter-overrides ${parameters}"
  eval "$cmd"
  log "Stack deployed: ${stack_name}"
}

get_output() {
  aws cloudformation describe-stacks \
    --stack-name "$1" --region "${AWS_REGION}" \
    --query "Stacks[0].Outputs[?OutputKey=='$2'].OutputValue" \
    --output text
}

# ── Phase 1: Base ─────────────────────────────────────────────────────────────
deploy_base() {
  header "Phase 1: VPC, KMS, Cognito, Route53, ACM"
  deploy_stack "${STACK_PREFIX}-base" "${CFN_DIR}/01-base.yaml" \
    "ProjectName=${PROJECT_NAME} Environment=${ENVIRONMENT} DomainName=${DOMAIN_NAME} HostedZoneId=${HOSTED_ZONE_ID}"

  info "Waiting for ACM certificate DNS validation..."
  CERT_ARN=$(get_output "${STACK_PREFIX}-base" "ACMCertificateArn")
  aws acm wait certificate-validated --certificate-arn "${CERT_ARN}" --region "${AWS_REGION}" \
    || warn "ACM validation timeout — check Route53 CNAME records"
}

# ── Phase 2: Security ─────────────────────────────────────────────────────────
deploy_security() {
  header "Phase 2: Security Groups & WAF"
  deploy_stack "${STACK_PREFIX}-security" "${CFN_DIR}/02-security.yaml" \
    "ProjectName=${PROJECT_NAME} Environment=${ENVIRONMENT}"
}

# ── Phase 3: IAM ──────────────────────────────────────────────────────────────
deploy_iam() {
  header "Phase 3: IAM Roles & Karpenter SQS/EventBridge"
  deploy_stack "${STACK_PREFIX}-iam" "${CFN_DIR}/03-iam.yaml" \
    "ProjectName=${PROJECT_NAME} Environment=${ENVIRONMENT}"
}

# ── Phase 4: VPC Endpoints ────────────────────────────────────────────────────
deploy_vpc_endpoints() {
  header "Phase 4: VPC Endpoints (ECR, STS, SM, KMS, SQS, EKS, EFS...)"
  deploy_stack "${STACK_PREFIX}-vpc-endpoints" "${CFN_DIR}/05-vpc-endpoints.yaml" \
    "ProjectName=${PROJECT_NAME} Environment=${ENVIRONMENT}"
  log "All AWS API traffic now routed via PrivateLink — NAT bypass"
}

# ── Phase 5: Observability (CloudWatch + Secrets Manager) ────────────────────
deploy_observability() {
  header "Phase 5: CloudWatch Log Groups, Alarms, Dashboard, Secrets Manager"
  local params="ProjectName=${PROJECT_NAME} Environment=${ENVIRONMENT}"
  [[ -n "${ALERT_EMAIL}" ]] && params+=" AlertEmail=${ALERT_EMAIL}"
  deploy_stack "${STACK_PREFIX}-observability" "${CFN_DIR}/06-observability.yaml" "${params}"

  # Update Cognito config secret with real values
  local pool_id client_id secret_arn
  pool_id=$(get_output "${STACK_PREFIX}-base" "CognitoUserPoolId")
  client_id=$(get_output "${STACK_PREFIX}-base" "CognitoUserPoolClientId")
  secret_arn=$(get_output "${STACK_PREFIX}-observability" "CognitoConfigSecretArn")
  info "Updating Cognito config secret..."
  aws secretsmanager put-secret-value \
    --secret-id "${secret_arn}" \
    --secret-string "$(jq -n \
        --arg pool  "${pool_id}" \
        --arg cid   "${client_id}" \
        --arg reg   "${AWS_REGION}" \
        --arg iss   "https://cognito-idp.${AWS_REGION}.amazonaws.com/${pool_id}" \
        '{user_pool_id:$pool,client_id:$cid,client_secret:"SET_MANUALLY",region:$reg,jwt_issuer:$iss}')" \
    --region "${AWS_REGION}"
  log "Cognito config secret updated"
}

# ── Phase 6: Cognito Event Pipeline + ECR + CodeBuild ────────────────────────
deploy_cognito_pipeline() {
  header "Phase 6: Cognito→CloudTrail→EventBridge→SQS, ECR, CodeBuild, CodePipeline"

  local params="ProjectName=${PROJECT_NAME} Environment=${ENVIRONMENT}"
  params+=" GitHubOwner=${GITHUB_OWNER}"
  params+=" GitHubRepo=${GITHUB_REPO}"
  params+=" GitHubBranch=${GITHUB_BRANCH}"
  params+=" GitHubHelmRepo=${GITHUB_HELM_REPO}"
  params+=" GitHubConnectionArn=${GITHUB_CONNECTION_ARN}"
  params+=" ECRRepositoryName=${ECR_REPO_NAME}"

  deploy_stack "${STACK_PREFIX}-cognito-pipeline" "${CFN_DIR}/07-cognito-pipeline-ecr-codebuild.yaml" "${params}"

  log "Cognito event pipeline, ECR repos, and CodeBuild projects created"
  info "NOTE: Set GitHub PAT in Secrets Manager:"
  info "  Secret: ${PROJECT_NAME}/${ENVIRONMENT}/github/token"
  info "  Keys: github_token, github_user"
}

# ── Phase 7: Rails IAM + EFS Access Points ────────────────────────────────────
deploy_rails_resources() {
  header "Phase 7: Rails Pod Identity Roles, EFS Access Points, SSH SG rule"
  deploy_stack "${STACK_PREFIX}-rails-resources" "${CFN_DIR}/08-rails-resources.yaml" \
    "ProjectName=${PROJECT_NAME} Environment=${ENVIRONMENT}"
  log "Rails IAM roles and EFS access points ready"
}

# ── Phase 8: EKS Cluster + EFS + RDS ─────────────────────────────────────────
deploy_eks_rds_efs() {
  header "Phase 8: EKS Cluster, Add-ons, EFS, RDS Aurora PostgreSQL"
  deploy_stack "${STACK_PREFIX}-eks-rds-efs" "${CFN_DIR}/04-eks-rds-efs.yaml" \
    "ProjectName=${PROJECT_NAME} Environment=${ENVIRONMENT}"

  info "Updating kubeconfig..."
  aws eks update-kubeconfig --name "${CLUSTER_NAME}" --region "${AWS_REGION}" --alias "${CLUSTER_NAME}"

  info "Waiting for EKS cluster ACTIVE..."
  aws eks wait cluster-active --name "${CLUSTER_NAME}" --region "${AWS_REGION}"
  log "EKS cluster active: ${CLUSTER_NAME}"
}

# ── Phase 9: Helm repos ───────────────────────────────────────────────────────
setup_helm_repos() {
  header "Phase 9: Helm Repositories"
  helm repo add karpenter           https://charts.karpenter.sh
  helm repo add aws-load-balancer   https://aws.github.io/eks-charts
  helm repo add argo                https://argoproj.github.io/argo-helm
  helm repo add metrics-server      https://kubernetes-sigs.github.io/metrics-server
  helm repo add external-secrets    https://charts.external-secrets.io
  helm repo add jetstack            https://charts.jetstack.io
  helm repo update
  log "Helm repos configured"
}

# ── Phase 10: Karpenter ───────────────────────────────────────────────────────
deploy_karpenter() {
  header "Phase 10: Karpenter"
  local role_arn queue_name node_role_arn ebs_key_arn
  role_arn=$(get_output "${STACK_PREFIX}-iam" "KarpenterControllerRoleArn")
  queue_name=$(get_output "${STACK_PREFIX}-iam" "KarpenterInterruptionQueueName")
  node_role_arn=$(get_output "${STACK_PREFIX}-iam" "EKSNodeRoleArn")
  ebs_key_arn=$(get_output "${STACK_PREFIX}-base" "EBSKMSKeyArn")

  kubectl create namespace karpenter --dry-run=client -o yaml | kubectl apply -f -
  aws eks create-pod-identity-association \
    --cluster-name "${CLUSTER_NAME}" --namespace karpenter \
    --service-account karpenter --role-arn "${role_arn}" \
    --region "${AWS_REGION}" 2>/dev/null || true

  helm upgrade --install karpenter karpenter/karpenter \
    --namespace karpenter --version "${KARPENTER_VERSION}" \
    --set "settings.clusterName=${CLUSTER_NAME}" \
    --set "settings.interruptionQueue=${queue_name}" \
    --set "serviceAccount.name=karpenter" \
    --set controller.resources.requests.cpu=250m \
    --set controller.resources.requests.memory=512Mi \
    --set replicas=2 \
    --node-selector role=karpenter-system \
    --tolerations '[{"key":"CriticalAddonsOnly","operator":"Exists","effect":"NoSchedule"}]' \
    --wait --timeout 5m

  local node_role_name="${node_role_arn##*/}"
  cat <<EOF | kubectl apply -f -
apiVersion: karpenter.k8s.aws/v1
kind: EC2NodeClass
metadata:
  name: default
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
        kmsKeyID: "${ebs_key_arn}"
        deleteOnTermination: true
  metadataOptions:
    httpTokens: required
    httpPutResponseHopLimit: 1
  tags:
    Project: "${PROJECT_NAME}"
    Environment: "${ENVIRONMENT}"
    ManagedBy: karpenter
---
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: default
spec:
  template:
    spec:
      nodeClassRef:
        group: karpenter.k8s.aws
        kind: EC2NodeClass
        name: default
      requirements:
        - key: karpenter.k8s.aws/instance-category
          operator: In
          values: [m, c, r]
        - key: karpenter.k8s.aws/instance-generation
          operator: Gt
          values: ["5"]
        - key: karpenter.sh/capacity-type
          operator: In
          values: [spot, on-demand]
  limits:
    cpu: "200"
    memory: 800Gi
  disruption:
    consolidationPolicy: WhenEmptyOrUnderutilized
    consolidateAfter: 1m
EOF
  log "Karpenter deployed"
}

# ── Phase 11: AWS Load Balancer Controller ────────────────────────────────────
deploy_alb_controller() {
  header "Phase 11: AWS Load Balancer Controller"
  local role_arn vpc_id
  role_arn=$(get_output "${STACK_PREFIX}-iam" "ALBControllerRoleArn")
  vpc_id=$(get_output "${STACK_PREFIX}-base" "VpcId")

  kubectl create namespace aws-load-balancer --dry-run=client -o yaml | kubectl apply -f -
  aws eks create-pod-identity-association \
    --cluster-name "${CLUSTER_NAME}" --namespace aws-load-balancer \
    --service-account aws-load-balancer-controller --role-arn "${role_arn}" \
    --region "${AWS_REGION}" 2>/dev/null || true

  helm upgrade --install aws-load-balancer-controller \
    aws-load-balancer-controller/aws-load-balancer-controller \
    --namespace aws-load-balancer --version "${ALB_CONTROLLER_VERSION}" \
    --set clusterName="${CLUSTER_NAME}" \
    --set serviceAccount.name=aws-load-balancer-controller \
    --set region="${AWS_REGION}" --set vpcId="${vpc_id}" \
    --set replicaCount=2 \
    --node-selector role=karpenter-system \
    --tolerations '[{"key":"CriticalAddonsOnly","operator":"Exists","effect":"NoSchedule"}]' \
    --wait --timeout 5m
  log "ALB Controller deployed"
}

# ── Phase 12: Storage Classes ─────────────────────────────────────────────────
deploy_storage_classes() {
  header "Phase 12: EBS & EFS Storage Classes"
  local ebs_key efs_id
  ebs_key=$(get_output "${STACK_PREFIX}-base" "EBSKMSKeyArn")
  efs_id=$(get_output "${STACK_PREFIX}-eks-rds-efs" "EFSFileSystemId")

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
# EFS StorageClass — ReadWriteMany, Multi-AZ safe
# Used by Rails gui and app servers instead of EBS
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
  log "Storage classes created (efs-sc is primary for Rails pods)"
}

# ── Phase 13: Metrics Server ──────────────────────────────────────────────────
deploy_metrics_server() {
  header "Phase 13: Metrics Server"
  helm upgrade --install metrics-server metrics-server/metrics-server \
    --namespace kube-system --version "${METRICS_SERVER_VERSION}" \
    --set replicas=2 --wait --timeout 3m
  log "Metrics server deployed"
}

# ── Phase 14: cert-manager ────────────────────────────────────────────────────
deploy_cert_manager() {
  header "Phase 14: cert-manager (SSH host key distribution for rsync sidecars)"

  helm upgrade --install cert-manager jetstack/cert-manager \
    --namespace cert-manager --create-namespace \
    --version "${CERT_MANAGER_VERSION}" \
    --set installCRDs=true \
    --set replicaCount=2 \
    --set webhook.replicaCount=2 \
    --set cainjector.replicaCount=2 \
    --node-selector role=karpenter-system \
    --tolerations '[{"key":"CriticalAddonsOnly","operator":"Exists","effect":"NoSchedule"}]' \
    --wait --timeout 5m

  info "Waiting for cert-manager webhooks to be ready..."
  kubectl wait --for=condition=ready pod \
    -l app.kubernetes.io/instance=cert-manager \
    -n cert-manager --timeout=120s

  # Apply ClusterIssuers (self-signed root + internal CA)
  kubectl apply -f "${ARGOCD_DIR}/cluster-issuers.yaml"

  # Wait for internal CA certificate to be issued
  info "Waiting for internal CA certificate..."
  local retries=20
  while [[ $retries -gt 0 ]]; do
    local ready
    ready=$(kubectl get certificate cluster-internal-ca -n cert-manager \
      -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "")
    [[ "${ready}" == "True" ]] && break
    sleep 5; ((retries--))
  done
  log "cert-manager and ClusterIssuers ready"
}

# ── Phase 15: ArgoCD ──────────────────────────────────────────────────────────
deploy_argocd() {
  header "Phase 15: ArgoCD (GitOps)"
  local role_arn cert_arn waf_arn alb_sg_id
  role_arn=$(get_output "${STACK_PREFIX}-iam" "ArgoCDRoleArn")
  cert_arn=$(get_output "${STACK_PREFIX}-base" "ACMCertificateArn")
  waf_arn=$(get_output "${STACK_PREFIX}-security" "WAFWebACLArn")
  alb_sg_id=$(get_output "${STACK_PREFIX}-security" "ALBSecurityGroupId")

  kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
  aws eks create-pod-identity-association \
    --cluster-name "${CLUSTER_NAME}" --namespace argocd \
    --service-account argocd-server --role-arn "${role_arn}" \
    --region "${AWS_REGION}" 2>/dev/null || true

  helm upgrade --install argocd argo/argo-cd \
    --namespace argocd --version "${ARGOCD_VERSION}" \
    --values - <<HELMVALUES
global:
  domain: argocd.${DOMAIN_NAME}
server:
  replicas: 2
  ingress:
    enabled: true
    ingressClassName: alb
    annotations:
      alb.ingress.kubernetes.io/scheme: internet-facing
      alb.ingress.kubernetes.io/target-type: ip
      alb.ingress.kubernetes.io/certificate-arn: "${cert_arn}"
      alb.ingress.kubernetes.io/ssl-policy: ELBSecurityPolicy-TLS13-1-2-2021-06
      alb.ingress.kubernetes.io/wafv2-acl-arn: "${waf_arn}"
      alb.ingress.kubernetes.io/security-groups: "${alb_sg_id}"
      alb.ingress.kubernetes.io/listen-ports: '[{"HTTP":80},{"HTTPS":443}]'
      alb.ingress.kubernetes.io/ssl-redirect: "443"
    hosts:
      - argocd.${DOMAIN_NAME}
repoServer:
  replicas: 2
applicationSet:
  replicas: 2
configs:
  params:
    server.insecure: true
  cm:
    url: https://argocd.${DOMAIN_NAME}
    exec.enabled: "false"
HELMVALUES

  kubectl wait --for=condition=ready pod \
    -l app.kubernetes.io/name=argocd-server -n argocd --timeout=300s

  local initial_pw
  initial_pw=$(kubectl get secret argocd-initial-admin-secret \
    -n argocd -o jsonpath='{.data.password}' | base64 -d)

  aws secretsmanager put-secret-value \
    --secret-id "${PROJECT_NAME}/${ENVIRONMENT}/argocd/admin-password" \
    --secret-string "${initial_pw}" --region "${AWS_REGION}" 2>/dev/null || \
  aws secretsmanager create-secret \
    --name "${PROJECT_NAME}/${ENVIRONMENT}/argocd/admin-password" \
    --secret-string "${initial_pw}" --region "${AWS_REGION}"

  log "ArgoCD deployed. Admin password saved to Secrets Manager."
}

# ── Phase 16: ArgoCD Rails project token ─────────────────────────────────────
configure_argocd_rails() {
  header "Phase 16: ArgoCD App-of-Apps, Rails project token, Helm repo"

  # Cluster-wide config
  local rds_ep rds_reader pool_id client_id efs_id db_secret sqs_url ecr_uri
  rds_ep=$(get_output     "${STACK_PREFIX}-eks-rds-efs"         "RDSClusterEndpoint")
  rds_reader=$(get_output "${STACK_PREFIX}-eks-rds-efs"         "RDSClusterReaderEndpoint")
  pool_id=$(get_output    "${STACK_PREFIX}-base"                 "CognitoUserPoolId")
  client_id=$(get_output  "${STACK_PREFIX}-base"                 "CognitoUserPoolClientId")
  efs_id=$(get_output     "${STACK_PREFIX}-eks-rds-efs"          "EFSFileSystemId")
  db_secret=$(get_output  "${STACK_PREFIX}-eks-rds-efs"          "DBSecretArn")
  sqs_url=$(get_output    "${STACK_PREFIX}-cognito-pipeline"      "CognitoEventQueueUrl")
  ecr_uri=$(get_output    "${STACK_PREFIX}-cognito-pipeline"      "ECRRepositoryUri")

  # Update cluster-config ConfigMap with all values Rails needs
  cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: cluster-config
  namespace: argocd
data:
  PROJECT_NAME:            "${PROJECT_NAME}"
  ENVIRONMENT:             "${ENVIRONMENT}"
  AWS_REGION:              "${AWS_REGION}"
  AWS_ACCOUNT_ID:          "${AWS_ACCOUNT_ID}"
  DOMAIN_NAME:             "${DOMAIN_NAME}"
  CLUSTER_NAME:            "${CLUSTER_NAME}"
  RDS_ENDPOINT:            "${rds_ep}"
  RDS_READER_ENDPOINT:     "${rds_reader}"
  COGNITO_USER_POOL_ID:    "${pool_id}"
  COGNITO_CLIENT_ID:       "${client_id}"
  EFS_FILE_SYSTEM_ID:      "${efs_id}"
  DB_SECRET_ARN:           "${db_secret}"
  COGNITO_SQS_QUEUE_URL:   "${sqs_url}"
  ECR_REPOSITORY_URI:      "${ecr_uri}"
  HELM_REPO_URL:           "https://${GITHUB_OWNER}.github.io/${GITHUB_HELM_REPO}"
  ARGOCD_SERVER:           "argocd-server.argocd.svc.cluster.local:443"
EOF

  # Apply ArgoCD AppProject and Helm repo secret for Rails workloads
  sed "s|HELM_REPO_URL_PLACEHOLDER|https://${GITHUB_OWNER}.github.io/${GITHUB_HELM_REPO}|g" \
    "${ARGOCD_DIR}/rails-apps.yaml" | kubectl apply -f -

  # Apply platform apps (cert-manager already deployed, this registers it in ArgoCD)
  sed "s|ARGOCD_REPO_URL_PLACEHOLDER|${ARGOCD_REPO_URL}|g" \
    "${ARGOCD_DIR}/platform-apps.yaml" | kubectl apply -f -

  # Generate ArgoCD API token for Rails deployer role and store in Secrets Manager
  info "Generating ArgoCD API token for Rails deployer..."
  local argocd_pw argocd_token
  argocd_pw=$(aws secretsmanager get-secret-value \
    --secret-id "${PROJECT_NAME}/${ENVIRONMENT}/argocd/admin-password" \
    --query SecretString --output text --region "${AWS_REGION}")

  # Login to ArgoCD CLI if available, else use curl
  if command -v argocd &>/dev/null; then
    argocd login "argocd.${DOMAIN_NAME}" \
      --username admin --password "${argocd_pw}" --grpc-web 2>/dev/null || true
    argocd_token=$(argocd account generate-token \
      --account rails-deployer --grpc-web 2>/dev/null || echo "")
  else
    # Fallback: curl ArgoCD API
    local argocd_jwt
    argocd_jwt=$(curl -sk "https://argocd.${DOMAIN_NAME}/api/v1/session" \
      -d "{\"username\":\"admin\",\"password\":\"${argocd_pw}\"}" \
      | jq -r '.token // empty')
    argocd_token=$(curl -sk "https://argocd.${DOMAIN_NAME}/api/v1/account/rails-deployer/token" \
      -H "Authorization: Bearer ${argocd_jwt}" -X POST \
      | jq -r '.token // empty')
  fi

  if [[ -n "${argocd_token}" ]]; then
    aws secretsmanager put-secret-value \
      --secret-id "${PROJECT_NAME}/${ENVIRONMENT}/argocd/rails-deployer-token" \
      --secret-string "{\"token\":\"${argocd_token}\"}" \
      --region "${AWS_REGION}" 2>/dev/null || \
    aws secretsmanager create-secret \
      --name "${PROJECT_NAME}/${ENVIRONMENT}/argocd/rails-deployer-token" \
      --secret-string "{\"token\":\"${argocd_token}\"}" \
      --region "${AWS_REGION}"
    log "ArgoCD Rails deployer token saved to Secrets Manager"
  else
    warn "Could not generate ArgoCD token automatically — do it manually:"
    warn "  argocd account generate-token --account rails-deployer"
    warn "  Store in: ${PROJECT_NAME}/${ENVIRONMENT}/argocd/rails-deployer-token"
  fi

  # Root App-of-Apps
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
      backoff: { duration: 5s, factor: 2, maxDuration: 3m }
EOF
  log "ArgoCD App-of-Apps configured"
}

# ── Phase 17: Pod Identity associations ──────────────────────────────────────
configure_pod_identities() {
  header "Phase 17: EKS Pod Identity Associations"

  local rails_role argocd_bridge_role ebs_role efs_role
  rails_role=$(get_output        "${STACK_PREFIX}-rails-resources"  "RailsPodRoleArn")
  argocd_bridge_role=$(get_output "${STACK_PREFIX}-rails-resources" "ArgoCDBridgeRoleArn")
  ebs_role=$(get_output          "${STACK_PREFIX}-iam"              "EBSCSIDriverRoleArn")
  efs_role=$(get_output          "${STACK_PREFIX}-iam"              "EFSCSIDriverRoleArn")

  # Helper function
  associate_pod_identity() {
    local ns="$1" sa="$2" role="$3"
    aws eks create-pod-identity-association \
      --cluster-name "${CLUSTER_NAME}" \
      --namespace "${ns}" --service-account "${sa}" \
      --role-arn "${role}" --region "${AWS_REGION}" 2>/dev/null || true
    info "  Associated: ${ns}/${sa} → ${role##*/}"
  }

  # Rails pods in any gui-* or app-* namespace inherit via the SA name convention.
  # For now, create associations for the 'rails-gui' and 'rails-app' namespaces.
  # When Rails Job creates a new namespace, it calls:
  #   aws eks create-pod-identity-association ... (handled in deploy_rails_namespace below)
  kubectl create namespace rails-system --dry-run=client -o yaml | kubectl apply -f -
  associate_pod_identity "rails-system" "rails-gui-sa"  "${rails_role}"
  associate_pod_identity "rails-system" "rails-app-sa"  "${rails_role}"

  # ArgoCD bridge SA (used by Rails Jobs to call ArgoCD API)
  associate_pod_identity "argocd"       "argocd-server"  "${argocd_bridge_role}"

  # EBS/EFS CSI
  associate_pod_identity "kube-system"  "ebs-csi-controller-sa" "${ebs_role}"
  associate_pod_identity "kube-system"  "efs-csi-controller-sa" "${efs_role}"

  log "Pod Identity associations configured"
}

# ── Phase 18: Container Insights ─────────────────────────────────────────────
install_container_insights() {
  header "Phase 18: CloudWatch Container Insights"
  local ci_role
  ci_role=$(get_output "${STACK_PREFIX}-observability" "ContainerInsightsRoleArn" 2>/dev/null || echo "")
  [[ -z "${ci_role}" ]] && { warn "ContainerInsightsRoleArn not found — skip"; return; }

  kubectl create namespace amazon-cloudwatch --dry-run=client -o yaml | kubectl apply -f -
  aws eks create-pod-identity-association \
    --cluster-name "${CLUSTER_NAME}" --namespace amazon-cloudwatch \
    --service-account cloudwatch-agent --role-arn "${ci_role}" \
    --region "${AWS_REGION}" 2>/dev/null || true

  aws eks create-addon \
    --cluster-name "${CLUSTER_NAME}" \
    --addon-name amazon-cloudwatch-observability \
    --region "${AWS_REGION}" 2>/dev/null || true

  info "Waiting for CloudWatch Observability addon..."
  local retries=24
  while [[ $retries -gt 0 ]]; do
    local status
    status=$(aws eks describe-addon \
      --cluster-name "${CLUSTER_NAME}" \
      --addon-name amazon-cloudwatch-observability \
      --region "${AWS_REGION}" \
      --query "addon.status" --output text 2>/dev/null || echo "UNKNOWN")
    [[ "${status}" == "ACTIVE" ]] && { log "Container Insights active"; return; }
    [[ "${status}" == *FAILED* ]] && { warn "Addon status: ${status}"; return; }
    sleep 15; ((retries--))
  done
}

# ── Phase 19: Route53 DNS ─────────────────────────────────────────────────────
configure_dns() {
  header "Phase 19: Route53 DNS Records"
  info "Waiting for ALB provisioning (up to 5 min)..."
  local retries=30 alb_dns=""
  while [[ $retries -gt 0 && -z "${alb_dns}" ]]; do
    alb_dns=$(kubectl get ingress -n argocd \
      -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
    [[ -z "${alb_dns}" ]] && { sleep 10; ((retries--)); }
  done

  if [[ -z "${alb_dns}" ]]; then
    warn "ALB not found — create Route53 records manually after deployment"
    return
  fi

  local alb_zone_id
  case "${AWS_REGION}" in
    ap-northeast-1) alb_zone_id="Z14GRHDCWA56QT" ;;
    us-east-1)      alb_zone_id="Z35SXDOTRQ7X7K" ;;
    us-west-2)      alb_zone_id="Z1H1FL5HABSF5"  ;;
    eu-west-1)      alb_zone_id="Z32O12XQLNTSW2" ;;
    *)              alb_zone_id="Z14GRHDCWA56QT" ;;
  esac

  aws route53 change-resource-record-sets \
    --hosted-zone-id "${HOSTED_ZONE_ID}" \
    --change-batch "$(jq -n \
        --arg dns "${alb_dns}" --arg zone "${alb_zone_id}" \
        --arg domain "${DOMAIN_NAME}" \
        '{Changes:[
          {Action:"UPSERT",ResourceRecordSet:{Name:$domain,Type:"A",
            AliasTarget:{HostedZoneId:$zone,DNSName:$dns,EvaluateTargetHealth:true}}},
          {Action:"UPSERT",ResourceRecordSet:{Name:("*." + $domain),Type:"A",
            AliasTarget:{HostedZoneId:$zone,DNSName:$dns,EvaluateTargetHealth:true}}}
        ]}')"
  log "Route53 DNS: *.${DOMAIN_NAME} → ${alb_dns}"
}

# ── Phase 20: Verify ──────────────────────────────────────────────────────────
verify_deployment() {
  header "Phase 20: Verification"
  kubectl get nodes -o wide
  kubectl get pods -A | grep -v Running | head -20
  kubectl get storageclass
  kubectl get nodepools 2>/dev/null || true
  kubectl get ingress -A
  kubectl get certificates -A 2>/dev/null || true
  log "Verification complete"
}

# ── Helper: deploy_rails_namespace (called by Rails Job) ──────────────────────
# This function shows the pattern Rails uses to prepare a new namespace.
# Rails executes these commands in a pre-hook Kubernetes Job before helm install.
deploy_rails_namespace() {
  local ns_type="${1}"       # "gui" or "app"
  local ns_id="${2}"         # user-id or project-id
  local namespace="${ns_type}-${ns_id}"
  local rails_role sa_name
  rails_role=$(get_output "${STACK_PREFIX}-rails-resources" "RailsPodRoleArn")
  sa_name="rails-${ns_type}-sa"

  info "Preparing namespace: ${namespace}"

  # 1. Create namespace with labels
  kubectl create namespace "${namespace}" --dry-run=client -o yaml | kubectl apply -f -
  kubectl label namespace "${namespace}" \
    "app.kubernetes.io/managed-by-rails=${ns_type}" \
    "app.kubernetes.io/ns-type=${ns_type}" \
    --overwrite

  # 2. Pod Identity association for this namespace's SA
  aws eks create-pod-identity-association \
    --cluster-name "${CLUSTER_NAME}" \
    --namespace "${namespace}" \
    --service-account "${sa_name}" \
    --role-arn "${rails_role}" \
    --region "${AWS_REGION}" 2>/dev/null || true

  # 3. Copy cluster-config ConfigMap into the namespace
  kubectl get configmap cluster-config -n argocd -o json \
    | jq ".metadata.namespace = \"${namespace}\" | del(.metadata.resourceVersion,.metadata.uid,.metadata.creationTimestamp)" \
    | kubectl apply -f -

  # 4. Copy ExternalSecret store reference
  cat <<EOF | kubectl apply -f -
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: db-credentials
  namespace: ${namespace}
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: aws-secretsmanager
    kind: ClusterSecretStore
  target:
    name: db-credentials
    creationPolicy: Owner
  data:
    - secretKey: DB_HOST
      remoteRef:
        key: ${PROJECT_NAME}/${ENVIRONMENT}/rds/master-credentials
        property: host
    - secretKey: DB_PORT
      remoteRef:
        key: ${PROJECT_NAME}/${ENVIRONMENT}/rds/master-credentials
        property: port
    - secretKey: DB_USERNAME
      remoteRef:
        key: ${PROJECT_NAME}/${ENVIRONMENT}/rds/master-credentials
        property: username
    - secretKey: DB_PASSWORD
      remoteRef:
        key: ${PROJECT_NAME}/${ENVIRONMENT}/rds/master-credentials
        property: password
EOF

  log "Namespace ${namespace} ready for helm install"
}

# ── Summary ───────────────────────────────────────────────────────────────────
print_summary() {
  header "🎉 Deployment Complete"
  local rds_ep pool_id sqs_url ecr_uri
  rds_ep=$(get_output  "${STACK_PREFIX}-eks-rds-efs"    "RDSClusterEndpoint"    2>/dev/null || echo "N/A")
  pool_id=$(get_output "${STACK_PREFIX}-base"           "CognitoUserPoolId"     2>/dev/null || echo "N/A")
  sqs_url=$(get_output "${STACK_PREFIX}-cognito-pipeline" "CognitoEventQueueUrl" 2>/dev/null || echo "N/A")
  ecr_uri=$(get_output "${STACK_PREFIX}-cognito-pipeline" "ECRRepositoryUri"     2>/dev/null || echo "N/A")

  cat <<SUMMARY
  ┌──────────────────────────────────────────────────────────────┐
  │                  Infrastructure Summary                       │
  ├──────────────────────────────────────────────────────────────┤
  │  Cluster:          ${CLUSTER_NAME}
  │  Region:           ${AWS_REGION}
  │  Domain:           ${DOMAIN_NAME}
  │  ArgoCD:           https://argocd.${DOMAIN_NAME}
  │  RDS Endpoint:     ${rds_ep}
  │  Cognito Pool:     ${pool_id}
  │  SQS (Cognito):    ${sqs_url}
  │  ECR (Rails):      ${ecr_uri}
  ├──────────────────────────────────────────────────────────────┤
  │  Next Steps:                                                 │
  │  1. Set GitHub PAT in Secrets Manager:                       │
  │     ${PROJECT_NAME}/${ENVIRONMENT}/github/token             │
  │  2. Change ArgoCD admin password                             │
  │  3. Push app manifests to ${ARGOCD_REPO_URL}                │
  │  4. Trigger first CodeBuild run                              │
  │  5. Configure Rails env: COGNITO_SQS_QUEUE_URL               │
  └──────────────────────────────────────────────────────────────┘
SUMMARY
}

# ── Destroy ───────────────────────────────────────────────────────────────────
destroy_all() {
  warn "⚠️  DESTROYING ALL RESOURCES"
  read -p "Type 'DELETE ${CLUSTER_NAME}' to confirm: " confirm
  [[ "${confirm}" != "DELETE ${CLUSTER_NAME}" ]] && { info "Cancelled."; exit 0; }

  for rel in argocd aws-load-balancer-controller karpenter cert-manager; do
    helm uninstall "$rel" -n "${rel%%-*}" 2>/dev/null || true
  done

  for stack in eks-rds-efs rails-resources cognito-pipeline observability vpc-endpoints iam security base; do
    aws cloudformation delete-stack --stack-name "${STACK_PREFIX}-${stack}" --region "${AWS_REGION}" 2>/dev/null || true
    aws cloudformation wait stack-delete-complete --stack-name "${STACK_PREFIX}-${stack}" --region "${AWS_REGION}" 2>/dev/null || true
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
      deploy_rails_resources
      deploy_eks_rds_efs
      setup_helm_repos
      deploy_karpenter
      deploy_alb_controller
      deploy_storage_classes
      deploy_metrics_server
      deploy_cert_manager
      deploy_argocd
      configure_argocd_rails
      configure_pod_identities
      install_container_insights
      configure_dns
      verify_deployment
      print_summary
      ;;
    destroy)         destroy_all ;;
    verify)          verify_deployment ;;
    dns)             configure_dns ;;
    cert-manager)    deploy_cert_manager ;;
    argocd)          deploy_argocd; configure_argocd_rails ;;
    karpenter)       deploy_karpenter ;;
    vpc-endpoints)   deploy_vpc_endpoints ;;
    observability)   deploy_observability ;;
    cognito-pipeline) deploy_cognito_pipeline ;;
    rails-resources) deploy_rails_resources ;;
    pod-identities)  configure_pod_identities ;;
    # Called by Rails Job pre-hook
    rails-namespace) deploy_rails_namespace "${2:-gui}" "${3:-default}" ;;
    *)
      echo "Usage: $0 {deploy|destroy|verify|dns|cert-manager|argocd|karpenter|"
      echo "          vpc-endpoints|observability|cognito-pipeline|rails-resources|"
      echo "          pod-identities|rails-namespace <gui|app> <id>}"
      echo ""
      echo "Required env vars:"
      echo "  PROJECT_NAME, ENVIRONMENT, AWS_REGION"
      echo "  DOMAIN_NAME, HOSTED_ZONE_ID"
      echo "  ARGOCD_REPO_URL"
      echo "  GITHUB_OWNER, GITHUB_REPO, GITHUB_CONNECTION_ARN"
      echo ""
      echo "Optional:"
      echo "  GITHUB_BRANCH (default: main)"
      echo "  GITHUB_HELM_REPO (default: helm-charts)"
      echo "  ECR_REPO_NAME (default: rails-app)"
      echo "  ALERT_EMAIL"
      exit 1
      ;;
  esac
}

main "$@"
