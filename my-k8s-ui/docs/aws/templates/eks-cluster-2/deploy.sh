#!/usr/bin/env bash
# =============================================================================
# EKS Cluster Full Deployment Script
# 前提: AWS CLI v2 設定済み、eksctl, helm, kubectl インストール済み
# =============================================================================
set -euo pipefail

# ---------------------------------------------------------------------------
# ★ 環境変数 - 必ず自環境に合わせて変更してください
# ---------------------------------------------------------------------------
export AWS_REGION="ap-northeast-1"
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# 既存リソース
export VPC_ID="vpc-xxxxxxxxxxxxxxxxx"
export EXISTING_PRIVATE_SUBNET_1="subnet-xxxxxxxxxxxxxxxxx"   # 踏み台用既存サブネット
export EXISTING_S3_ENDPOINT_ID="vpce-xxxxxxxxxxxxxxxxx"       # 既存S3 GatewayEndpoint
export EXISTING_ENDPOINT_ROUTE_TABLE_ID="rtb-xxxxxxxxxxxxxxxxx" # 既存エンドポイント用ルートテーブル

# 新規サブネット CIDR (VPC CIDRに合わせて調整)
export EKS_SUBNET_1_CIDR="10.0.10.0/24"
export EKS_SUBNET_2_CIDR="10.0.11.0/24"
export ENDPOINT_SUBNET_CIDR="10.0.12.0/24"
export AZ_1="ap-northeast-1a"
export AZ_2="ap-northeast-1c"

# EKS
export CLUSTER_NAME="private-eks-cluster"
export EKS_VERSION="1.31"
export NODE_INSTANCE_TYPE="m6i.xlarge"
export NODE_MIN=2
export NODE_MAX=2
export NODE_DESIRED=2

# RDS
export DB_INSTANCE_CLASS="db.t3.medium"
export DB_NAME="appdb"
export DB_PORT=5432

# S3バケット (CFnアーティファクト・Helm chart用)
export CFN_BUCKET="${AWS_ACCOUNT_ID}-cfn-artifacts-${AWS_REGION}"
export HELM_BUCKET="${AWS_ACCOUNT_ID}-helm-charts-${AWS_REGION}"

# CodeArtifact
export CODEARTIFACT_DOMAIN="myorg"
export CODEARTIFACT_REPO="internal"

# GitOps
export GITOPS_REPO_URL="https://git-codecommit.${AWS_REGION}.amazonaws.com/v1/repos/eks-gitops"

# Cognito
export COGNITO_DOMAIN_PREFIX="myapp-auth"

# プロジェクトタグ
export PROJECT_TAG="my-eks-project"
export ENV_TAG="production"

# ---------------------------------------------------------------------------
# ユーティリティ関数
# ---------------------------------------------------------------------------
log()  { echo -e "\033[1;34m[INFO]\033[0m  $*"; }
warn() { echo -e "\033[1;33m[WARN]\033[0m  $*"; }
die()  { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; exit 1; }

wait_stack() {
  local stack_name="$1"
  log "Waiting for stack: ${stack_name} ..."
  aws cloudformation wait stack-create-complete --stack-name "${stack_name}" 2>/dev/null || \
  aws cloudformation wait stack-update-complete --stack-name "${stack_name}" 2>/dev/null || true
  local status
  status=$(aws cloudformation describe-stacks --stack-name "${stack_name}" \
    --query 'Stacks[0].StackStatus' --output text 2>/dev/null || echo "DOES_NOT_EXIST")
  if [[ "${status}" == *"FAILED"* ]] || [[ "${status}" == *"ROLLBACK"* ]]; then
    die "Stack ${stack_name} failed: ${status}"
  fi
  log "Stack ${stack_name} completed: ${status}"
}

deploy_stack() {
  local stack_name="$1"
  local template_file="$2"
  shift 2
  local params=("$@")

  log "Deploying stack: ${stack_name}"
  aws cloudformation deploy \
    --stack-name "${stack_name}" \
    --template-file "${template_file}" \
    --parameter-overrides "${params[@]}" \
    --capabilities CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND \
    --tags Project="${PROJECT_TAG}" Environment="${ENV_TAG}" \
    --no-fail-on-empty-changeset
  wait_stack "${stack_name}"
}

get_output() {
  local stack_name="$1"
  local key="$2"
  aws cloudformation describe-stacks --stack-name "${stack_name}" \
    --query "Stacks[0].Outputs[?OutputKey=='${key}'].OutputValue" --output text
}

# ---------------------------------------------------------------------------
# Step 0: S3バケット作成 (CFNアーティファクト用)
# ---------------------------------------------------------------------------
step0_s3_buckets() {
  log "=== Step 0: S3バケット作成 ==="
  for bucket in "${CFN_BUCKET}" "${HELM_BUCKET}"; do
    if ! aws s3api head-bucket --bucket "${bucket}" 2>/dev/null; then
      aws s3api create-bucket --bucket "${bucket}" --region "${AWS_REGION}" \
        --create-bucket-configuration LocationConstraint="${AWS_REGION}"
      aws s3api put-bucket-versioning --bucket "${bucket}" \
        --versioning-configuration Status=Enabled
      aws s3api put-bucket-encryption --bucket "${bucket}" \
        --server-side-encryption-configuration \
        '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"aws:kms"}}]}'
      aws s3api put-public-access-block --bucket "${bucket}" \
        --public-access-block-configuration \
        'BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true'
      log "Created bucket: ${bucket}"
    else
      log "Bucket already exists: ${bucket}"
    fi
  done
}

# ---------------------------------------------------------------------------
# Step 1: KMS キー
# ---------------------------------------------------------------------------
step1_kms() {
  log "=== Step 1: KMS キー作成 ==="
  deploy_stack "${CLUSTER_NAME}-kms" \
    "templates/02-kms.yaml" \
    "ClusterName=${CLUSTER_NAME}" \
    "ProjectTag=${PROJECT_TAG}"
  export KMS_EKS_KEY_ARN=$(get_output "${CLUSTER_NAME}-kms" "EksSecretsKeyArn")
  export KMS_EBS_KEY_ARN=$(get_output "${CLUSTER_NAME}-kms" "EbsKeyArn")
  export KMS_RDS_KEY_ARN=$(get_output "${CLUSTER_NAME}-kms" "RdsKeyArn")
  export KMS_S3_KEY_ARN=$(get_output "${CLUSTER_NAME}-kms" "S3KeyArn")
  export KMS_SQS_KEY_ARN=$(get_output "${CLUSTER_NAME}-kms" "SqsKeyArn")
  log "KMS Keys created."
}

# ---------------------------------------------------------------------------
# Step 2: サブネット & VPC Endpoint
# ---------------------------------------------------------------------------
step2_network() {
  log "=== Step 2: サブネット & VPC Endpoints ==="
  deploy_stack "${CLUSTER_NAME}-network" \
    "templates/01-subnets-endpoints.yaml" \
    "VpcId=${VPC_ID}" \
    "ClusterName=${CLUSTER_NAME}" \
    "EksSubnet1Cidr=${EKS_SUBNET_1_CIDR}" \
    "EksSubnet2Cidr=${EKS_SUBNET_2_CIDR}" \
    "EndpointSubnetCidr=${ENDPOINT_SUBNET_CIDR}" \
    "Az1=${AZ_1}" \
    "Az2=${AZ_2}" \
    "ExistingS3EndpointId=${EXISTING_S3_ENDPOINT_ID}"

  export EKS_SUBNET_1=$(get_output "${CLUSTER_NAME}-network" "EksSubnet1Id")
  export EKS_SUBNET_2=$(get_output "${CLUSTER_NAME}-network" "EksSubnet2Id")
  export ENDPOINT_SUBNET=$(get_output "${CLUSTER_NAME}-network" "EndpointSubnetId")
  export EKS_SG=$(get_output "${CLUSTER_NAME}-network" "EksClusterSgId")
  export NODE_SG=$(get_output "${CLUSTER_NAME}-network" "NodeSgId")
  export RDS_SG=$(get_output "${CLUSTER_NAME}-network" "RdsSgId")
  export EFS_SG=$(get_output "${CLUSTER_NAME}-network" "EfsSgId")
  log "Network resources created."
}

# ---------------------------------------------------------------------------
# Step 3: IAM ロール
# ---------------------------------------------------------------------------
step3_iam() {
  log "=== Step 3: IAM ロール作成 ==="
  deploy_stack "${CLUSTER_NAME}-iam" \
    "templates/03-iam.yaml" \
    "ClusterName=${CLUSTER_NAME}" \
    "AccountId=${AWS_ACCOUNT_ID}" \
    "Region=${AWS_REGION}" \
    "HelmBucket=${HELM_BUCKET}" \
    "CodeArtifactDomain=${CODEARTIFACT_DOMAIN}" \
    "ProjectTag=${PROJECT_TAG}"

  export EKS_CLUSTER_ROLE=$(get_output "${CLUSTER_NAME}-iam" "EksClusterRoleArn")
  export EKS_NODE_ROLE=$(get_output "${CLUSTER_NAME}-iam" "EksNodeRoleArn")
  export CODEBUILD_ROLE=$(get_output "${CLUSTER_NAME}-iam" "CodeBuildRoleArn")
  log "IAM roles created."
}

# ---------------------------------------------------------------------------
# Step 4: ECR & CodeArtifact
# ---------------------------------------------------------------------------
step4_ecr_codeartifact() {
  log "=== Step 4: ECR & CodeArtifact ==="
  deploy_stack "${CLUSTER_NAME}-ecr" \
    "templates/04-ecr-codeartifact.yaml" \
    "ClusterName=${CLUSTER_NAME}" \
    "CodeArtifactDomain=${CODEARTIFACT_DOMAIN}" \
    "CodeArtifactRepo=${CODEARTIFACT_REPO}" \
    "KmsS3KeyArn=${KMS_S3_KEY_ARN}" \
    "HelmBucket=${HELM_BUCKET}"

  export APP_ECR_URI=$(get_output "${CLUSTER_NAME}-ecr" "AppEcrUri")
  export RAILS_ECR_URI=$(get_output "${CLUSTER_NAME}-ecr" "RailsEcrUri")
  export BUILD_ECR_URI=$(get_output "${CLUSTER_NAME}-ecr" "BuildEcrUri")
  log "ECR & CodeArtifact created."
}

# ---------------------------------------------------------------------------
# Step 5: ストレージ (RDS, EFS)
# ---------------------------------------------------------------------------
step5_storage() {
  log "=== Step 5: RDS & EFS ==="
  # DBパスワードをSecrets Managerに保存
  local secret_arn
  secret_arn=$(aws secretsmanager create-secret \
    --name "${CLUSTER_NAME}/rds/password" \
    --generate-secret-string \
    '{"SecretStringTemplate":"{\"username\":\"postgres\"}","GenerateStringKey":"password","PasswordLength":32,"ExcludeCharacters":"\"@/\\"}' \
    --kms-key-id "${KMS_RDS_KEY_ARN}" \
    --query ARN --output text 2>/dev/null || \
    aws secretsmanager describe-secret --secret-id "${CLUSTER_NAME}/rds/password" \
      --query ARN --output text)

  deploy_stack "${CLUSTER_NAME}-storage" \
    "templates/05-storage.yaml" \
    "ClusterName=${CLUSTER_NAME}" \
    "VpcId=${VPC_ID}" \
    "EksSubnet1=${EKS_SUBNET_1}" \
    "EksSubnet2=${EKS_SUBNET_2}" \
    "RdsSg=${RDS_SG}" \
    "EfsSg=${EFS_SG}" \
    "KmsRdsKeyArn=${KMS_RDS_KEY_ARN}" \
    "KmsEbsKeyArn=${KMS_EBS_KEY_ARN}" \
    "DbInstanceClass=${DB_INSTANCE_CLASS}" \
    "DbName=${DB_NAME}" \
    "DbSecretArn=${secret_arn}"

  export RDS_ENDPOINT=$(get_output "${CLUSTER_NAME}-storage" "RdsEndpoint")
  export EFS_ID=$(get_output "${CLUSTER_NAME}-storage" "EfsId")
  log "RDS endpoint: ${RDS_ENDPOINT}, EFS ID: ${EFS_ID}"
}

# ---------------------------------------------------------------------------
# Step 6: メッセージング (Cognito, SQS, EventBridge)
# ---------------------------------------------------------------------------
step6_messaging() {
  log "=== Step 6: Cognito, SQS, EventBridge ==="
  deploy_stack "${CLUSTER_NAME}-messaging" \
    "templates/06-messaging.yaml" \
    "ClusterName=${CLUSTER_NAME}" \
    "CognitoDomainPrefix=${COGNITO_DOMAIN_PREFIX}" \
    "KmsSqsKeyArn=${KMS_SQS_KEY_ARN}"

  export COGNITO_USER_POOL_ID=$(get_output "${CLUSTER_NAME}-messaging" "CognitoUserPoolId")
  export COGNITO_CLIENT_ID=$(get_output "${CLUSTER_NAME}-messaging" "CognitoClientId")
  export USER_EVENTS_QUEUE_URL=$(get_output "${CLUSTER_NAME}-messaging" "UserEventsQueueUrl")
  export USER_EVENTS_QUEUE_ARN=$(get_output "${CLUSTER_NAME}-messaging" "UserEventsQueueArn")
  log "Cognito Pool: ${COGNITO_USER_POOL_ID}, SQS: ${USER_EVENTS_QUEUE_URL}"
}

# ---------------------------------------------------------------------------
# Step 7: EKS クラスタ & Managed Node Group
# ---------------------------------------------------------------------------
step7_eks() {
  log "=== Step 7: EKS クラスタ & Managed Node Group ==="
  deploy_stack "${CLUSTER_NAME}-eks" \
    "templates/07-eks.yaml" \
    "ClusterName=${CLUSTER_NAME}" \
    "EksVersion=${EKS_VERSION}" \
    "EksClusterRoleArn=${EKS_CLUSTER_ROLE}" \
    "EksNodeRoleArn=${EKS_NODE_ROLE}" \
    "EksSubnet1=${EKS_SUBNET_1}" \
    "EksSubnet2=${EKS_SUBNET_2}" \
    "EksClusterSg=${EKS_SG}" \
    "NodeSg=${NODE_SG}" \
    "KmsEksKeyArn=${KMS_EKS_KEY_ARN}" \
    "KmsEbsKeyArn=${KMS_EBS_KEY_ARN}" \
    "NodeInstanceType=${NODE_INSTANCE_TYPE}" \
    "NodeMin=${NODE_MIN}" \
    "NodeMax=${NODE_MAX}" \
    "NodeDesired=${NODE_DESIRED}"

  export EKS_CLUSTER_ARN=$(get_output "${CLUSTER_NAME}-eks" "ClusterArn")
  export EKS_OIDC_URL=$(get_output "${CLUSTER_NAME}-eks" "OidcUrl")
  export EKS_OIDC_ARN=$(get_output "${CLUSTER_NAME}-eks" "OidcProviderArn")
  log "EKS Cluster ARN: ${EKS_CLUSTER_ARN}"
  log "OIDC URL: ${EKS_OIDC_URL}"

  # kubeconfig 更新
  aws eks update-kubeconfig --name "${CLUSTER_NAME}" --region "${AWS_REGION}"
}

# ---------------------------------------------------------------------------
# Step 8: CodeBuild
# ---------------------------------------------------------------------------
step8_codebuild() {
  log "=== Step 8: CodeBuild ==="
  deploy_stack "${CLUSTER_NAME}-codebuild" \
    "templates/08-codebuild.yaml" \
    "ClusterName=${CLUSTER_NAME}" \
    "CodeBuildRoleArn=${CODEBUILD_ROLE}" \
    "AppEcrUri=${APP_ECR_URI}" \
    "RailsEcrUri=${RAILS_ECR_URI}" \
    "BuildEcrUri=${BUILD_ECR_URI}" \
    "HelmBucket=${HELM_BUCKET}" \
    "CodeArtifactDomain=${CODEARTIFACT_DOMAIN}" \
    "CodeArtifactRepo=${CODEARTIFACT_REPO}" \
    "VpcId=${VPC_ID}" \
    "EksSubnet1=${EKS_SUBNET_1}" \
    "EksSubnet2=${EKS_SUBNET_2}" \
    "GitopsRepoUrl=${GITOPS_REPO_URL}"
  log "CodeBuild projects created."
}

# ---------------------------------------------------------------------------
# Step 9: IRSA ロール (EKS OIDC 取得後)
# ---------------------------------------------------------------------------
step9_irsa() {
  log "=== Step 9: IRSA ロール ==="
  local oidc_id
  oidc_id=$(echo "${EKS_OIDC_URL}" | sed 's|https://||')
  deploy_stack "${CLUSTER_NAME}-irsa" \
    "templates/03b-irsa.yaml" \
    "ClusterName=${CLUSTER_NAME}" \
    "OidcProviderArn=${EKS_OIDC_ARN}" \
    "OidcProviderId=${oidc_id}" \
    "AccountId=${AWS_ACCOUNT_ID}" \
    "Region=${AWS_REGION}" \
    "EfsId=${EFS_ID}" \
    "HelmBucket=${HELM_BUCKET}" \
    "UserEventsQueueArn=${USER_EVENTS_QUEUE_ARN}" \
    "KmsEbsKeyArn=${KMS_EBS_KEY_ARN}" \
    "KmsS3KeyArn=${KMS_S3_KEY_ARN}" \
    "KmsSqsKeyArn=${KMS_SQS_KEY_ARN}" \
    "RdsClustedId=${CLUSTER_NAME}-rds"

  export KARPENTER_ROLE_ARN=$(get_output "${CLUSTER_NAME}-irsa" "KarpenterRoleArn")
  export EBS_CSI_ROLE_ARN=$(get_output "${CLUSTER_NAME}-irsa" "EbsCsiRoleArn")
  export EFS_CSI_ROLE_ARN=$(get_output "${CLUSTER_NAME}-irsa" "EfsCsiRoleArn")
  export LBC_ROLE_ARN=$(get_output "${CLUSTER_NAME}-irsa" "LbcRoleArn")
  export ARGOCD_ROLE_ARN=$(get_output "${CLUSTER_NAME}-irsa" "ArgoCdRoleArn")
  export RAILS_APP_ROLE_ARN=$(get_output "${CLUSTER_NAME}-irsa" "RailsAppRoleArn")
  log "IRSA roles created."
}

# ---------------------------------------------------------------------------
# Step 10: Helm アドオンインストール
# ---------------------------------------------------------------------------
step10_helm_addons() {
  log "=== Step 10: Helm アドオンインストール ==="
  scripts/post-install.sh \
    "${CLUSTER_NAME}" \
    "${AWS_REGION}" \
    "${AWS_ACCOUNT_ID}" \
    "${EKS_NODE_ROLE}" \
    "${KARPENTER_ROLE_ARN}" \
    "${EBS_CSI_ROLE_ARN}" \
    "${EFS_CSI_ROLE_ARN}" \
    "${LBC_ROLE_ARN}" \
    "${ARGOCD_ROLE_ARN}" \
    "${EFS_ID}" \
    "${GITOPS_REPO_URL}"
}

# ---------------------------------------------------------------------------
# メイン
# ---------------------------------------------------------------------------
main() {
  log "============================================"
  log "EKS Cluster Deployment Start"
  log "Cluster: ${CLUSTER_NAME} / Region: ${AWS_REGION}"
  log "============================================"

  step0_s3_buckets
  step1_kms
  step2_network
  step3_iam
  step4_ecr_codeartifact
  step5_storage
  step6_messaging
  step7_eks
  step8_codebuild
  step9_irsa
  step10_helm_addons

  log "============================================"
  log "Deployment Complete!"
  log "EKS Cluster: ${CLUSTER_NAME}"
  log "RDS Endpoint: ${RDS_ENDPOINT}"
  log "EFS ID: ${EFS_ID}"
  log "Cognito Pool: ${COGNITO_USER_POOL_ID}"
  log "============================================"
}

main "$@"
