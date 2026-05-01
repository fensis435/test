# EKS プライベートクラスタ 自動構築ガイド

## アーキテクチャ概要

```
VPC (完全プライベート / NATなし / IGWなし)
│
├── 既存サブネット
│   └── 踏み台EC2 (SSM経由アクセス)
│
├── EKSサブネット-1 (AZ-a)  ← EKSノード / RDS / EFS
├── EKSサブネット-2 (AZ-c)  ← EKSノード / RDS / EFS
│
└── VPCエンドポイント専用サブネット
    └── 全インターフェース型VPCエンドポイント (25個)
        ACM / CloudTrail / CodeBuild / CodeArtifact(api+repo)
        ECR-API / ECR-DKR / EC2 / STS / CWLogs / CWMonitoring
        SecretsManager / EKS / EFS / KMS / SQS
        SSM / SSMMessages / EC2Messages / AutoScaling / ELB
        ※ S3はGateway型(既存)
```

```
EKS クラスタ (完全プライベートエンドポイント)
│
├── Managed Node Group (管理用) ← 常時2台固定
│   taint: dedicated=management:NoSchedule
│   ├── ArgoCD (GitOps)
│   ├── Karpenter (動的ノード管理)
│   ├── Rails v8 アプリ ×2 (WebUI + ユーザ管理)
│   ├── Rails Worker (SQS Consumer)
│   ├── EBS/EFS CSI Driver
│   ├── AWS Load Balancer Controller
│   ├── External Secrets Operator
│   └── Metrics Server / Container Insights
│
└── Karpenter 動的ノード (計算用Pod)
    └── 計算ワーカー Pod (必要時のみ起動)
        PV: EBS(ReadWriteOnce) + EFS(ReadWriteMany)
```

```
CI/CD パイプライン (GitOps)
│
CodeCommit (main push)
  └─▶ EventBridge
        └─▶ CodeBuild (Ubuntu 24 ベースコンテナ)
              ├── git diff で変更サービス検出
              ├── Docker build (AlmaLinux9)
              │   └── dnf/pip/npm/gem → CodeArtifact経由
              ├── ECR push
              ├── helm package → S3 push
              └── gitops/apps/*/values.yaml (imageTag更新) → git push
                    └─▶ ArgoCD が検出して自動sync
```

```
認証フロー
┌─────────────┐    HTTPS(ALB)    ┌──────────────┐
│ ブラウザ     │ ───────────────▶ │ ALB Internal │
└─────────────┘                  └──────┬───────┘
                                        │ Cognito認証委任
                                 ┌──────▼────────────────┐
                                 │ Cognito User Pool     │
                                 │ (JWT発行 / OIDC)      │
                                 └──────┬────────────────┘
                                        │ JWT (id_token)
                                 ┌──────▼───────┐
                                 │ Rails Pod    │
                                 │ JWT検証(JWKS)│
                                 │ IRSA → AWS   │
                                 └──────┬───────┘
                                        │
                    ┌───────────────────┼──────────────────┐
                    ▼                   ▼                  ▼
              RDS Proxy           SQS (FIFO)          S3 (EFS)
           (PostgreSQL 15)   ユーザイベントキュー    アプリデータ
```

```
ユーザ管理フロー
Cognito イベント
  └─▶ CloudTrail → EventBridge
                     └─▶ SQS (FIFO キュー)
                           └─▶ Rails Worker (Solid Queue)
                                 └─▶ ローカルDB同期
                                       + Cognito管理API
```

---

## ディレクトリ構成

```
eks-cluster/
├── deploy.sh                    # メインデプロイスクリプト
├── scripts/
│   ├── post-install.sh          # Helm アドオンインストール
│   ├── ops.sh                   # 運用コマンド集
│   └── destroy.sh               # 全リソース削除
├── templates/                   # CloudFormation テンプレート
│   ├── 01-subnets-endpoints.yaml   # サブネット + VPCエンドポイント25個
│   ├── 02-kms.yaml                 # KMSキー6種
│   ├── 03-iam.yaml                 # EKSクラスター/ノード/CodeBuildロール
│   ├── 03b-irsa.yaml               # IRSAロール7種
│   ├── 04-ecr-codeartifact.yaml    # ECRリポジトリ + CodeArtifact
│   ├── 05-storage.yaml             # RDS Proxy + EFS
│   ├── 06-messaging.yaml           # Cognito + SQS + EventBridge
│   ├── 07-eks.yaml                 # EKSクラスタ + MNG + OIDCプロバイダ
│   └── 08-codebuild.yaml           # CodeBuildプロジェクト
├── helm/
│   └── charts/
│       ├── rails-app/              # Rails v8 管理アプリ Helmチャート
│       └── compute-worker/         # 計算Pod Helmチャート
├── gitops/
│   └── apps/
│       └── rails-app/values.yaml   # ArgoCD が監視するGitOps values
├── dockerfiles/
│   ├── Dockerfile.build            # Ubuntu24 ビルドコンテナ
│   ├── Dockerfile.rails            # AlmaLinux9 Rails アプリ
│   ├── Dockerfile.compute          # AlmaLinux9 計算Pod
│   └── docker-entrypoint-rails.sh  # Railsエントリーポイント
└── apps/
    └── rails/
        ├── config/initializers/
        │   └── cognito_and_sqs.rb  # JWT認証 + SQS Consumer
        └── app/controllers/
            └── application_controller.rb  # 認証Concern + UsersAPI
```

---

## 前提条件

| ツール | バージョン | 用途 |
|--------|-----------|------|
| AWS CLI | v2.19+ | AWS操作 |
| kubectl | v1.31+ | k8s操作 |
| helm | v3.16+ | チャート管理 |
| eksctl | latest | EKSアクセスエントリ管理 |

### 踏み台EC2 へのインストール
```bash
# AWS CLI v2
curl -fsSL https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip -o awscliv2.zip
unzip awscliv2.zip && sudo ./aws/install

# kubectl
curl -LO "https://dl.k8s.io/release/v1.31.0/bin/linux/amd64/kubectl"
chmod +x kubectl && sudo mv kubectl /usr/local/bin/

# helm
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# helm-s3プラグイン
helm plugin install https://github.com/hypnoglow/helm-s3.git
```

---

## デプロイ手順

### Step 1: 変数設定
```bash
# deploy.sh の以下の変数を環境に合わせて変更
vim deploy.sh
# 必須変更項目:
#   VPC_ID
#   EXISTING_PRIVATE_SUBNET_1
#   EXISTING_S3_ENDPOINT_ID
#   EKS_SUBNET_1_CIDR / EKS_SUBNET_2_CIDR / ENDPOINT_SUBNET_CIDR
#   CLUSTER_NAME
#   GITOPS_REPO_URL
#   COGNITO_DOMAIN_PREFIX
```

### Step 2: SSM で踏み台にログイン
```bash
aws ssm start-session --target i-xxxxxxxxxxxx --region ap-northeast-1
```

### Step 3: デプロイ実行
```bash
chmod +x deploy.sh scripts/*.sh
./deploy.sh
```

> 所要時間の目安: 約45〜60分

### Step 4: EKS クラスタ接続確認
```bash
kubectl get nodes
kubectl get pods -A
```

---

## Karpenter による動的スケール

計算ジョブを実行する場合は、Karpenter の NodePool に従ってノードが自動起動します。

```yaml
# 計算Podの例 (compute namespace)
apiVersion: batch/v1
kind: Job
metadata:
  name: my-compute-job
  namespace: compute
spec:
  template:
    spec:
      serviceAccountName: compute-job
      nodeSelector:
        role: compute
      containers:
        - name: worker
          image: <ECR_URI>/compute:latest
          resources:
            requests:
              cpu: "4"
              memory: 16Gi
          volumeMounts:
            - name: local
              mountPath: /data/local
            - name: shared
              mountPath: /data/shared
      volumes:
        - name: local
          persistentVolumeClaim:
            claimName: job-ebs-pvc
        - name: shared
          persistentVolumeClaim:
            claimName: efs-shared-pvc
      restartPolicy: Never
```

---

## CodeArtifact リポジトリ経由のパッケージ利用

```bash
# pip
export CODEARTIFACT_TOKEN=$(aws codeartifact get-authorization-token \
  --domain myorg --query authorizationToken --output text)
pip install numpy --index-url \
  "https://aws:${CODEARTIFACT_TOKEN}@myorg-ACCOUNT.d.codeartifact.REGION.amazonaws.com/pypi/internal/simple/"

# gem (Bundler)
bundle config mirror.https://rubygems.org \
  "https://aws:${CODEARTIFACT_TOKEN}@myorg-ACCOUNT.d.codeartifact.REGION.amazonaws.com/ruby/internal-gems/"

# npm
npm config set registry \
  "https://myorg-ACCOUNT.d.codeartifact.REGION.amazonaws.com/npm/internal-npm/"
```

---

## KMS 暗号化対象一覧

| 対象 | KMSキー |
|------|---------|
| EKS Secrets (etcd) | `alias/CLUSTER-eks-secrets` |
| EBS ボリューム | `alias/CLUSTER-ebs` |
| RDS for PostgreSQL | `alias/CLUSTER-rds` |
| S3 バケット | `alias/CLUSTER-s3` |
| SQS キュー | `alias/CLUSTER-sqs` |
| Secrets Manager | `alias/CLUSTER-secrets` |

---

## IRSA ロール一覧

| サービスアカウント | namespace | ロール名 | 権限 |
|----------------|-----------|---------|------|
| karpenter | karpenter | CLUSTER-karpenter | EC2起動/終了, SQS受信 |
| ebs-csi-controller-sa | kube-system | CLUSTER-ebs-csi | EBS操作, KMS |
| efs-csi-controller-sa | kube-system | CLUSTER-efs-csi | EFS操作 |
| aws-load-balancer-controller | kube-system | CLUSTER-lbc | ELB操作 |
| argocd-* | argocd | CLUSTER-argocd | S3(Helm), CodeCommit |
| rails-app | app | CLUSTER-rails-app | RDS-IAM, SQS, Cognito, S3 |
| compute-job | compute | CLUSTER-compute-job | S3, RDS-IAM, Secrets |

---

## トラブルシューティング

### Podが起動しない
```bash
kubectl describe pod <pod-name> -n <namespace>
kubectl logs <pod-name> -n <namespace> --previous
```

### Karpenter がノードを起動しない
```bash
./scripts/ops.sh karpenter-status
kubectl describe nodeclaim <claim-name>
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter | tail -50
```

### ArgoCD 同期失敗
```bash
kubectl get applications -n argocd
kubectl describe application <app-name> -n argocd
./scripts/ops.sh argocd-sync <app-name>
```

### ECR からイメージをpullできない
```bash
# IRSAロールのECR権限を確認
aws sts get-caller-identity  # Pod内から実行
aws ecr get-login-password | docker login ...
```

### VPCエンドポイント接続確認
```bash
# 踏み台EC2から
curl -v https://ecr.api.ap-northeast-1.amazonaws.com
curl -v https://sts.amazonaws.com
nslookup ecr.api.ap-northeast-1.amazonaws.com
```

---

## コスト最適化のポイント

1. **Karpenter Spot優先**: `compute-spot` NodePoolはSpot→On-Demandの順で選択
2. **Karpenter Consolidation**: `WhenEmptyOrUnderutilized` で使われていないノードを自動削除
3. **RDS gp3**: Provisioned IOPS不要の場合はgp3が安価
4. **EFS Lifecycle**: 30日アクセスなしでIA(低頻度アクセス)に自動移行
5. **ECR Lifecycle Policy**: 古いイメージを自動削除
6. **S3 Lifecycle**: 90日→STANDARD_IA、365日→GLACIER
