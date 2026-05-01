#!/usr/bin/env bash
# =============================================================================
# post-install.sh
# EKS クラスタへ Helm アドオンをインストールするスクリプト
# 呼び出し元: deploy.sh step10_helm_addons
# =============================================================================
set -euo pipefail

CLUSTER_NAME="${1}"
AWS_REGION="${2}"
AWS_ACCOUNT_ID="${3}"
EKS_NODE_ROLE="${4}"
KARPENTER_ROLE_ARN="${5}"
EBS_CSI_ROLE_ARN="${6}"
EFS_CSI_ROLE_ARN="${7}"
LBC_ROLE_ARN="${8}"
ARGOCD_ROLE_ARN="${9}"
EFS_ID="${10}"
GITOPS_REPO_URL="${11}"

log()  { echo -e "\033[1;34m[HELM]\033[0m  $*"; }
die()  { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Helm repo 追加
# ---------------------------------------------------------------------------
setup_helm_repos() {
  log "=== Helm repos セットアップ ==="
  helm repo add eks        https://aws.github.io/eks-charts
  helm repo add karpenter  oci://public.ecr.aws/karpenter
  helm repo add argo       https://argoproj.github.io/argo-helm
  helm repo add metrics    https://kubernetes-sigs.github.io/metrics-server/
  helm repo add prometheus https://prometheus-community.github.io/helm-charts
  helm repo update
}

# ---------------------------------------------------------------------------
# 1. EBS CSI Driver
# ---------------------------------------------------------------------------
install_ebs_csi() {
  log "=== EBS CSI Driver インストール ==="
  kubectl create namespace kube-system --dry-run=client -o yaml | kubectl apply -f -

  kubectl annotate serviceaccount ebs-csi-controller-sa \
    -n kube-system \
    eks.amazonaws.com/role-arn="${EBS_CSI_ROLE_ARN}" \
    --overwrite 2>/dev/null || true

  helm upgrade --install aws-ebs-csi-driver eks/aws-ebs-csi-driver \
    --namespace kube-system \
    --set controller.serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="${EBS_CSI_ROLE_ARN}" \
    --set controller.serviceAccount.create=true \
    --set controller.serviceAccount.name=ebs-csi-controller-sa \
    --set defaultStorageClass.enabled=false \
    --set node.tolerateAllTaints=false \
    --wait --timeout 5m

  # StorageClass 作成 (KMS暗号化 gp3)
  kubectl apply -f - <<EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ebs-sc
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: ebs.csi.aws.com
volumeBindingMode: WaitForFirstConsumer
reclaimPolicy: Retain
allowVolumeExpansion: true
parameters:
  type: gp3
  iops: "3000"
  throughput: "125"
  encrypted: "true"
  kmsKeyId: "$(aws cloudformation describe-stacks \
    --stack-name ${CLUSTER_NAME}-kms \
    --query 'Stacks[0].Outputs[?OutputKey==`EbsKeyArn`].OutputValue' \
    --output text)"
EOF

  log "EBS CSI Driver インストール完了"
}

# ---------------------------------------------------------------------------
# 2. EFS CSI Driver
# ---------------------------------------------------------------------------
install_efs_csi() {
  log "=== EFS CSI Driver インストール ==="

  helm upgrade --install aws-efs-csi-driver eks/aws-efs-csi-driver \
    --namespace kube-system \
    --set controller.serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="${EFS_CSI_ROLE_ARN}" \
    --set controller.serviceAccount.create=true \
    --set controller.serviceAccount.name=efs-csi-controller-sa \
    --set node.serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="${EFS_CSI_ROLE_ARN}" \
    --wait --timeout 5m

  # EFS StorageClass
  kubectl apply -f - <<EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: efs-sc
provisioner: efs.csi.aws.com
reclaimPolicy: Retain
volumeBindingMode: Immediate
parameters:
  provisioningMode: efs-ap
  fileSystemId: "${EFS_ID}"
  directoryPerms: "700"
  gidRangeStart: "1000"
  gidRangeEnd: "2000"
  basePath: "/dynamic"
---
# 静的バインド用 PV (共有データ)
apiVersion: v1
kind: PersistentVolume
metadata:
  name: efs-shared-pv
spec:
  capacity:
    storage: 100Gi
  volumeMode: Filesystem
  accessModes:
    - ReadWriteMany
  persistentVolumeReclaimPolicy: Retain
  storageClassName: efs-sc
  csi:
    driver: efs.csi.aws.com
    volumeHandle: "${EFS_ID}::$(aws cloudformation describe-stacks \
      --stack-name ${CLUSTER_NAME}-storage \
      --query 'Stacks[0].Outputs[?OutputKey==`EfsSharedAccessPointId`].OutputValue' \
      --output text)"
EOF

  log "EFS CSI Driver インストール完了"
}

# ---------------------------------------------------------------------------
# 3. AWS Load Balancer Controller
# ---------------------------------------------------------------------------
install_lbc() {
  log "=== AWS Load Balancer Controller インストール ==="

  helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
    --namespace kube-system \
    --set clusterName="${CLUSTER_NAME}" \
    --set serviceAccount.create=true \
    --set serviceAccount.name=aws-load-balancer-controller \
    --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="${LBC_ROLE_ARN}" \
    --set region="${AWS_REGION}" \
    --set vpcId="$(aws eks describe-cluster \
      --name ${CLUSTER_NAME} \
      --query 'cluster.resourcesVpcConfig.vpcId' --output text)" \
    --set enableShield=false \
    --set enableWaf=false \
    --set enableWafv2=false \
    --wait --timeout 5m

  log "AWS Load Balancer Controller インストール完了"
}

# ---------------------------------------------------------------------------
# 4. Karpenter
# ---------------------------------------------------------------------------
install_karpenter() {
  log "=== Karpenter インストール ==="

  local KARPENTER_VERSION="1.1.0"
  local CLUSTER_ENDPOINT
  CLUSTER_ENDPOINT=$(aws eks describe-cluster \
    --name "${CLUSTER_NAME}" \
    --query "cluster.endpoint" --output text)
  local KARPENTER_QUEUE_NAME
  KARPENTER_QUEUE_NAME=$(aws cloudformation describe-stacks \
    --stack-name "${CLUSTER_NAME}-messaging" \
    --query 'Stacks[0].Outputs[?OutputKey==`KarpenterInterruptionQueueName`].OutputValue' \
    --output text)
  local NODE_ROLE_NAME
  NODE_ROLE_NAME=$(echo "${EKS_NODE_ROLE}" | rev | cut -d/ -f1 | rev)

  kubectl create namespace karpenter --dry-run=client -o yaml | kubectl apply -f -

  # Karpenter の NodeRole を aws-auth (または EKS Access Entry) に追加
  # EKS Access Entry API を使う
  aws eks create-access-entry \
    --cluster-name "${CLUSTER_NAME}" \
    --principal-arn "$(aws iam get-role \
      --role-name "${NODE_ROLE_NAME}" \
      --query 'Role.Arn' --output text)" \
    --type EC2_LINUX 2>/dev/null || log "Access entry already exists (skip)"

  helm upgrade --install karpenter oci://public.ecr.aws/karpenter/karpenter \
    --version "${KARPENTER_VERSION}" \
    --namespace karpenter \
    --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="${KARPENTER_ROLE_ARN}" \
    --set settings.clusterName="${CLUSTER_NAME}" \
    --set settings.clusterEndpoint="${CLUSTER_ENDPOINT}" \
    --set settings.interruptionQueue="${KARPENTER_QUEUE_NAME}" \
    --set settings.featureGates.spotToSpotConsolidation=true \
    --set controller.resources.requests.cpu=250m \
    --set controller.resources.requests.memory=512Mi \
    --set controller.resources.limits.cpu=1 \
    --set controller.resources.limits.memory=1Gi \
    --set tolerations[0].key=dedicated \
    --set tolerations[0].value=management \
    --set tolerations[0].effect=NoSchedule \
    --set nodeSelector.role=management \
    --wait --timeout 5m

  # Karpenter NodeClass & NodePool 適用
  apply_karpenter_resources

  log "Karpenter インストール完了"
}

apply_karpenter_resources() {
  local EKS_SUBNET_1
  EKS_SUBNET_1=$(aws cloudformation describe-stacks \
    --stack-name "${CLUSTER_NAME}-network" \
    --query 'Stacks[0].Outputs[?OutputKey==`EksSubnet1Id`].OutputValue' \
    --output text)
  local EKS_SUBNET_2
  EKS_SUBNET_2=$(aws cloudformation describe-stacks \
    --stack-name "${CLUSTER_NAME}-network" \
    --query 'Stacks[0].Outputs[?OutputKey==`EksSubnet2Id`].OutputValue' \
    --output text)
  local NODE_SG
  NODE_SG=$(aws cloudformation describe-stacks \
    --stack-name "${CLUSTER_NAME}-network" \
    --query 'Stacks[0].Outputs[?OutputKey==`NodeSgId`].OutputValue' \
    --output text)
  local LAUNCH_TEMPLATE_ID
  LAUNCH_TEMPLATE_ID=$(aws cloudformation describe-stacks \
    --stack-name "${CLUSTER_NAME}-eks" \
    --query 'Stacks[0].Outputs[?OutputKey==`LaunchTemplateId`].OutputValue' \
    --output text)

  kubectl apply -f - <<EOF
# ---------------------------------------------------------------------------
# EC2NodeClass: Karpenterが起動するノードのベース設定
# ---------------------------------------------------------------------------
apiVersion: karpenter.k8s.aws/v1
kind: EC2NodeClass
metadata:
  name: compute-default
spec:
  amiSelectorTerms:
    # AlmaLinux 9 ベースのEKS最適化AMI (SSMパラメータで最新版を取得)
    - alias: al2023@latest
  role: "${NODE_ROLE_NAME}"
  subnetSelectorTerms:
    - id: "${EKS_SUBNET_1}"
    - id: "${EKS_SUBNET_2}"
  securityGroupSelectorTerms:
    - id: "${NODE_SG}"
  # EBS設定 (KMS暗号化 gp3)
  blockDeviceMappings:
    - deviceName: /dev/xvda
      ebs:
        volumeSize: 50Gi
        volumeType: gp3
        iops: 3000
        throughput: 125
        encrypted: true
        kmsKeyID: "$(aws cloudformation describe-stacks \
          --stack-name ${CLUSTER_NAME}-kms \
          --query 'Stacks[0].Outputs[?OutputKey==`EbsKeyArn`].OutputValue' \
          --output text)"
        deleteOnTermination: true
  metadataOptions:
    httpEndpoint: enabled
    httpPutResponseHopLimit: 2
    httpTokens: required
  tags:
    Name: "${CLUSTER_NAME}-karpenter-node"
    "kubernetes.io/cluster/${CLUSTER_NAME}": owned
---
# ---------------------------------------------------------------------------
# NodePool: 計算用Pod向け (Spot優先)
# ---------------------------------------------------------------------------
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: compute-spot
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
        name: compute-default
      requirements:
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["spot", "on-demand"]
        - key: kubernetes.io/arch
          operator: In
          values: ["amd64"]
        - key: karpenter.k8s.aws/instance-family
          operator: In
          values: ["m6i", "m6a", "m5", "c6i", "c6a", "r6i"]
        - key: karpenter.k8s.aws/instance-size
          operator: In
          values: ["xlarge", "2xlarge", "4xlarge", "8xlarge"]
        - key: topology.kubernetes.io/zone
          operator: In
          values: ["ap-northeast-1a", "ap-northeast-1c"]
      taints: []
      terminationGracePeriod: 48h
  limits:
    cpu: "500"
    memory: 2000Gi
  disruption:
    consolidationPolicy: WhenEmptyOrUnderutilized
    consolidateAfter: 5m
    budgets:
      - nodes: "10%"
        schedule: "0 9 * * 1-5"
        duration: 8h
---
# NodePool: GPU 計算用 (オプション)
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: compute-gpu
spec:
  template:
    metadata:
      labels:
        role: compute-gpu
    spec:
      nodeClassRef:
        group: karpenter.k8s.aws
        kind: EC2NodeClass
        name: compute-default
      requirements:
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["spot", "on-demand"]
        - key: karpenter.k8s.aws/instance-family
          operator: In
          values: ["p3", "p4d", "g5"]
        - key: kubernetes.io/arch
          operator: In
          values: ["amd64"]
      taints:
        - key: "nvidia.com/gpu"
          effect: NoSchedule
  limits:
    cpu: "100"
    memory: 400Gi
  disruption:
    consolidationPolicy: WhenEmpty
    consolidateAfter: 30m
EOF
}

# ---------------------------------------------------------------------------
# 5. ArgoCD (GitOps)
# ---------------------------------------------------------------------------
install_argocd() {
  log "=== ArgoCD インストール ==="

  kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

  local HELM_BUCKET
  HELM_BUCKET="${AWS_ACCOUNT_ID}-helm-charts-${AWS_REGION}"

  helm upgrade --install argocd argo/argo-cd \
    --namespace argocd \
    --version "7.7.7" \
    --set server.service.type=ClusterIP \
    --set server.extraArgs[0]="--insecure" \
    --set controller.serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="${ARGOCD_ROLE_ARN}" \
    --set server.serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="${ARGOCD_ROLE_ARN}" \
    --set repoServer.serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="${ARGOCD_ROLE_ARN}" \
    --set configs.params."server\.insecure"=true \
    --set global.tolerations[0].key=dedicated \
    --set global.tolerations[0].value=management \
    --set global.tolerations[0].effect=NoSchedule \
    --set global.nodeSelector.role=management \
    --set configs.cm."timeout\.reconciliation"="60s" \
    --set configs.cm."resource\.customizations\.health\.argoproj\.io_Application"="" \
    --wait --timeout 10m

  # ArgoCD Secret (admin パスワード取得)
  log "ArgoCD admin password:"
  kubectl -n argocd get secret argocd-initial-admin-secret \
    -o jsonpath="{.data.password}" | base64 -d && echo

  # OIDC (Cognito) 設定
  apply_argocd_cognito_config

  # GitOps ApplicationSet 作成
  apply_argocd_applications

  log "ArgoCD インストール完了"
}

apply_argocd_cognito_config() {
  local COGNITO_POOL_ID
  COGNITO_POOL_ID=$(aws cloudformation describe-stacks \
    --stack-name "${CLUSTER_NAME}-messaging" \
    --query 'Stacks[0].Outputs[?OutputKey==`CognitoUserPoolId`].OutputValue' \
    --output text)
  local COGNITO_CLIENT_ID
  COGNITO_CLIENT_ID=$(aws cloudformation describe-stacks \
    --stack-name "${CLUSTER_NAME}-messaging" \
    --query 'Stacks[0].Outputs[?OutputKey==`CognitoClientId`].OutputValue' \
    --output text)
  local COGNITO_CLIENT_SECRET
  COGNITO_CLIENT_SECRET=$(aws cognito-idp describe-user-pool-client \
    --user-pool-id "${COGNITO_POOL_ID}" \
    --client-id "${COGNITO_CLIENT_ID}" \
    --query 'UserPoolClient.ClientSecret' --output text)

  kubectl apply -n argocd -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: argocd-secret
  namespace: argocd
  labels:
    app.kubernetes.io/part-of: argocd
type: Opaque
stringData:
  oidc.cognito.clientSecret: "${COGNITO_CLIENT_SECRET}"
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-cm
  namespace: argocd
  labels:
    app.kubernetes.io/part-of: argocd
data:
  url: "https://argocd.${CLUSTER_NAME}.internal"
  oidc.config: |
    name: Cognito
    issuer: "https://cognito-idp.${AWS_REGION}.amazonaws.com/${COGNITO_POOL_ID}"
    clientID: "${COGNITO_CLIENT_ID}"
    clientSecret: \$oidc.cognito.clientSecret
    requestedScopes:
      - openid
      - email
      - profile
    requestedIDTokenClaims:
      email:
        essential: true
  resource.customizations.ignoreDifferences.admissionregistration.k8s.io_MutatingWebhookConfiguration: |
    jqPathExpressions:
      - '.webhooks[]?.clientConfig.caBundle'
  resource.customizations.ignoreDifferences.admissionregistration.k8s.io_ValidatingWebhookConfiguration: |
    jqPathExpressions:
      - '.webhooks[]?.clientConfig.caBundle'
EOF
}

apply_argocd_applications() {
  log "ArgoCD ApplicationSet 作成..."
  kubectl apply -f - <<EOF
# ---------------------------------------------------------------------------
# ApplicationSet: GitOpsリポジトリの apps/ 以下を自動検出してデプロイ
# ---------------------------------------------------------------------------
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: apps-gitops
  namespace: argocd
spec:
  goTemplate: true
  goTemplateOptions: ["missingkey=error"]
  generators:
    - git:
        repoURL: "${GITOPS_REPO_URL}"
        revision: HEAD
        directories:
          - path: "gitops/apps/*"
  template:
    metadata:
      name: "{{.path.basename}}"
      namespace: argocd
      finalizers:
        - resources-finalizer.argocd.argoproj.io
    spec:
      project: default
      source:
        repoURL: "${GITOPS_REPO_URL}"
        targetRevision: HEAD
        path: "{{.path.path}}"
      destination:
        server: https://kubernetes.default.svc
        namespace: "{{.path.basename}}"
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
          allowEmpty: false
        syncOptions:
          - CreateNamespace=true
          - PrunePropagationPolicy=foreground
          - PruneLast=true
        retry:
          limit: 5
          backoff:
            duration: 5s
            factor: 2
            maxDuration: 3m
---
# ApplicationSet: インフラ系アドオン (Helm charts from S3)
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: infra-addons
  namespace: argocd
spec:
  generators:
    - list:
        elements:
          - name: rails-app
            namespace: app
            chart: rails-app
          - name: compute-worker
            namespace: compute
            chart: compute-worker
  template:
    metadata:
      name: "infra-{{name}}"
      namespace: argocd
    spec:
      project: default
      source:
        repoURL: "s3://${AWS_ACCOUNT_ID}-helm-charts-${AWS_REGION}/charts"
        chart: "{{chart}}"
        targetRevision: "*"
      destination:
        server: https://kubernetes.default.svc
        namespace: "{{namespace}}"
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
          - CreateNamespace=true
EOF
}

# ---------------------------------------------------------------------------
# 6. Metrics Server
# ---------------------------------------------------------------------------
install_metrics_server() {
  log "=== Metrics Server インストール ==="
  helm upgrade --install metrics-server metrics/metrics-server \
    --namespace kube-system \
    --set args[0]="--kubelet-insecure-tls" \
    --set tolerations[0].key=dedicated \
    --set tolerations[0].value=management \
    --set tolerations[0].effect=NoSchedule \
    --set nodeSelector.role=management \
    --wait --timeout 3m
  log "Metrics Server インストール完了"
}

# ---------------------------------------------------------------------------
# 7. Container Insights (CloudWatch)
# ---------------------------------------------------------------------------
install_container_insights() {
  log "=== CloudWatch Container Insights セットアップ ==="

  # FluentBit + CloudWatch エージェント
  local FLUENT_BIT_ROLE_ARN
  FLUENT_BIT_ROLE_ARN=$(aws iam get-role \
    --role-name "${CLUSTER_NAME}-eks-node-role" \
    --query 'Role.Arn' --output text)

  # Container Insights with Enhanced Observability
  aws eks create-addon \
    --cluster-name "${CLUSTER_NAME}" \
    --addon-name amazon-cloudwatch-observability \
    --service-account-role-arn "${FLUENT_BIT_ROLE_ARN}" \
    --resolve-conflicts OVERWRITE 2>/dev/null || \
  aws eks update-addon \
    --cluster-name "${CLUSTER_NAME}" \
    --addon-name amazon-cloudwatch-observability 2>/dev/null || true

  log "Container Insights セットアップ完了"
}

# ---------------------------------------------------------------------------
# 8. 名前空間と基本 RBAC の作成
# ---------------------------------------------------------------------------
setup_namespaces() {
  log "=== 名前空間 & RBAC 作成 ==="

  kubectl apply -f - <<EOF
# app 名前空間 (Rails管理アプリ)
apiVersion: v1
kind: Namespace
metadata:
  name: app
  labels:
    team: platform
    env: production
---
# compute 名前空間 (Karpenter計算Podq)
apiVersion: v1
kind: Namespace
metadata:
  name: compute
  labels:
    team: data
    env: production
---
# monitoring 名前空間
apiVersion: v1
kind: Namespace
metadata:
  name: monitoring
  labels:
    team: platform
---
# 管理用 ServiceAccount (Rails app)
apiVersion: v1
kind: ServiceAccount
metadata:
  name: rails-app
  namespace: app
  annotations:
    eks.amazonaws.com/role-arn: "$(aws cloudformation describe-stacks \
      --stack-name ${CLUSTER_NAME}-irsa \
      --query 'Stacks[0].Outputs[?OutputKey==`RailsAppRoleArn`].OutputValue' \
      --output text)"
---
# 計算用 ServiceAccount
apiVersion: v1
kind: ServiceAccount
metadata:
  name: compute-job
  namespace: compute
  annotations:
    eks.amazonaws.com/role-arn: "$(aws cloudformation describe-stacks \
      --stack-name ${CLUSTER_NAME}-irsa \
      --query 'Stacks[0].Outputs[?OutputKey==`ComputeJobRoleArn`].OutputValue' \
      --output text)"
---
# NetworkPolicy: app 名前空間内のみ通信許可 + 必要な外部
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: app-default
  namespace: app
spec:
  podSelector: {}
  policyTypes:
    - Ingress
    - Egress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: app
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: argocd
  egress:
    - {}   # egress は全許可 (VPC Endpoint経由のみ到達可能)
---
# LimitRange: デフォルトリソース制限
apiVersion: v1
kind: LimitRange
metadata:
  name: default-limits
  namespace: app
spec:
  limits:
    - default:
        memory: 512Mi
        cpu: 500m
      defaultRequest:
        memory: 128Mi
        cpu: 100m
      type: Container
---
apiVersion: v1
kind: LimitRange
metadata:
  name: default-limits
  namespace: compute
spec:
  limits:
    - default:
        memory: 8Gi
        cpu: "4"
      defaultRequest:
        memory: 1Gi
        cpu: "1"
      type: Container
EOF

  log "名前空間 & RBAC 作成完了"
}

# ---------------------------------------------------------------------------
# 9. Secrets Manager から Kubernetes Secret を同期 (External Secrets Operator)
# ---------------------------------------------------------------------------
install_external_secrets() {
  log "=== External Secrets Operator インストール ==="

  helm repo add external-secrets https://charts.external-secrets.io
  helm repo update

  helm upgrade --install external-secrets external-secrets/external-secrets \
    --namespace external-secrets \
    --create-namespace \
    --set installCRDs=true \
    --set tolerations[0].key=dedicated \
    --set tolerations[0].value=management \
    --set tolerations[0].effect=NoSchedule \
    --set nodeSelector.role=management \
    --wait --timeout 5m

  # ClusterSecretStore (Secrets Manager バックエンド)
  kubectl apply -f - <<EOF
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: aws-secrets-manager
spec:
  provider:
    aws:
      service: SecretsManager
      region: "${AWS_REGION}"
      auth:
        jwt:
          serviceAccountRef:
            name: external-secrets
            namespace: external-secrets
---
# RDS接続情報の ExternalSecret (app名前空間)
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: rds-secret
  namespace: app
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: aws-secrets-manager
    kind: ClusterSecretStore
  target:
    name: rds-credentials
    creationPolicy: Owner
  data:
    - secretKey: username
      remoteRef:
        key: "${CLUSTER_NAME}/rds/password"
        property: username
    - secretKey: password
      remoteRef:
        key: "${CLUSTER_NAME}/rds/password"
        property: password
EOF

  log "External Secrets Operator インストール完了"
}

# ---------------------------------------------------------------------------
# メイン実行
# ---------------------------------------------------------------------------
main() {
  log "==========================================="
  log "Helm アドオン インストール開始"
  log "クラスタ: ${CLUSTER_NAME}"
  log "==========================================="

  # kubectl接続確認
  kubectl cluster-info || die "kubectl がクラスタに接続できません"

  setup_helm_repos
  setup_namespaces
  install_ebs_csi
  install_efs_csi
  install_lbc
  install_karpenter
  install_metrics_server
  install_external_secrets
  install_argocd
  install_container_insights

  log "==========================================="
  log "全 Helm アドオン インストール完了"
  log "==========================================="

  # 最終確認
  log "--- Pod 状態確認 ---"
  kubectl get pods -A | grep -v Running | grep -v Completed | grep -v NAME || true
  log "--- StorageClass 確認 ---"
  kubectl get sc
  log "--- NodePool 確認 ---"
  kubectl get nodepools 2>/dev/null || true
}

main "$@"
