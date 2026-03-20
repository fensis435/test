# EKS Production Infrastructure

AWS EKS フルスタックインフラストラクチャの自動化スクリプト。

## アーキテクチャ概要

```
Internet
    │
    ▼
Route53 (DNS) ──► ACM (SSL/TLS証明書)
    │
    ▼
WAF v2 (AWSマネージドルール + レート制限)
    │
    ▼
ALB (Application Load Balancer) ◄── Cognito認証 (JWT)
    │
    ▼ (Private Subnets)
EKS Cluster
├── Karpenter (EC2動的スケーリング)
│   ├── NodePool: default (spot/on-demand, m/c/r系)
│   └── NodePool: gpu (g/p系, Taint付き)
├── AWS Load Balancer Controller
├── EBS CSI Driver (PV: gp3暗号化)
├── EFS CSI Driver (PV: ReadWriteMany)
├── ArgoCD (GitOps)
└── External Secrets Operator
    │
    ├── Pods (Pod Identity → IAM Role)
    │   ├── EBS PVC (ReadWriteOnce, KMS暗号化)
    │   ├── EFS PVC (ReadWriteMany, KMS暗号化)
    │   └── RDS接続 (Secrets Manager経由)
    │
    ▼ (DB Subnets - isolated)
RDS Aurora PostgreSQL
├── Writer Instance
└── Reader Instance

KMS Keys:
├── eks-secrets-key  (Kubernetes Secrets暗号化)
├── rds-key          (RDS暗号化)
├── ebs-key          (EBSボリューム暗号化)
└── efs-key          (EFS暗号化)
```

## ファイル構成

```
eks-infra/
├── cloudformation/
│   ├── 01-base.yaml        # VPC, KMS, Cognito, Route53, ACM
│   ├── 02-security.yaml    # Security Groups, WAF v2
│   ├── 03-iam.yaml         # IAM Roles, Karpenter SQS/EventBridge
│   └── 04-eks-rds-efs.yaml # EKS Cluster, Add-ons, EFS, RDS
├── scripts/
│   └── deploy.sh           # メインデプロイスクリプト
├── helm/
│   └── app-values.yaml     # アプリケーション Helm values テンプレート
└── argocd/
    ├── applications.yaml   # ArgoCD App-of-Apps設定
    └── k8s-manifests.yaml  # Kubernetes マニフェスト例
```

## 前提条件

```bash
# 必要ツール
brew install awscli kubectl helm jq

# AWS CLI 設定
aws configure
# または
export AWS_PROFILE=your-profile
```

## デプロイ手順

### 1. 環境変数を設定

```bash
export PROJECT_NAME="myapp"
export ENVIRONMENT="prod"
export AWS_REGION="ap-northeast-1"
export DOMAIN_NAME="myapp.example.com"
export HOSTED_ZONE_ID="Z1234567890ABC"        # Route53 Hosted Zone ID
export ARGOCD_REPO_URL="https://github.com/org/gitops-repo"
export ARGOCD_REPO_PATH="apps"
```

### 2. フルデプロイ実行

```bash
chmod +x scripts/deploy.sh
./scripts/deploy.sh deploy
```

デプロイは以下の順序で実行されます（約30〜45分）:

| Phase | 内容 | 所要時間 |
|-------|------|----------|
| 1 | VPC, KMS, Cognito, ACM | ~10分 |
| 2 | Security Groups, WAF | ~3分 |
| 3 | IAM Roles, Karpenter SQS | ~3分 |
| 4 | EKS Cluster, EFS, RDS | ~15分 |
| 5-9 | Helm: Karpenter, ALB, StorageClass, Metrics | ~5分 |
| 10-12 | ArgoCD, GitOps設定, DNS | ~5分 |

### 3. 部分デプロイ（個別フェーズ）

```bash
# ArgoCD のみ再デプロイ
./scripts/deploy.sh argocd

# Karpenter のみ再デプロイ
./scripts/deploy.sh karpenter

# DNS レコードのみ更新
./scripts/deploy.sh dns

# デプロイ状態確認
./scripts/deploy.sh verify
```

### 4. 削除

```bash
./scripts/deploy.sh destroy
# 確認: "DELETE myapp-prod" と入力
```

## GitOps (ArgoCD) 設定

### Git リポジトリ構成例

```
gitops-repo/
├── apps/                      # ArgoCD が監視するディレクトリ
│   ├── root-app.yaml          # App-of-Apps ルート
│   ├── app/                   # アプリケーション
│   │   ├── Chart.yaml
│   │   ├── values.yaml
│   │   └── values-prod.yaml
│   └── ...
└── platform/
    ├── namespaces/
    └── secret-stores/
```

### ArgoCD アクセス

```bash
# 初期パスワード確認
aws secretsmanager get-secret-value \
  --secret-id "myapp/prod/argocd/admin-password" \
  --query SecretString --output text

# ブラウザでアクセス
open https://argocd.myapp.example.com
```

## Karpenter スケーリング

```bash
# NodePool 確認
kubectl get nodepools

# ノード状態確認
kubectl get nodes -l karpenter.sh/nodepool=default

# スケールアップテスト
kubectl run test --image=nginx --requests='cpu=1,memory=1Gi'
kubectl get nodes -w

# スケールダウン確認 (Karpenter が自動で統合)
kubectl delete pod test
```

## Cognito JWT 認証フロー

```
1. ユーザーがブラウザから https://myapp.example.com にアクセス
2. ALB が Cognito ホストされたUIにリダイレクト
3. ユーザーがログイン (メール/パスワード, MFA)
4. Cognito が JWT (IdToken, AccessToken) を発行
5. ALB が JWT を検証 → アプリにリクエストをプロキシ
6. アプリが X-Amzn-Oidc-Data ヘッダーでユーザー情報取得
7. アプリは必要に応じて Cognito API で追加属性取得

JWT Claims:
- sub: ユーザーID
- email: メールアドレス
- custom:role: カスタム属性 (例: admin, user)
- exp: 有効期限
```

## セキュリティのポイント

| 項目 | 設定 |
|------|------|
| EKS Secrets | KMS暗号化 (AES-256) |
| EBS | KMS暗号化, gp3 |
| EFS | KMS暗号化, TLS強制 |
| RDS | KMS暗号化, SSL強制, IAM認証 |
| Pods | Pod Identity (IRSAより安全), Non-root, ReadOnlyRootFS |
| EC2 | IMDSv2強制, hop limit=1 |
| ALB | TLS 1.3, WAF, Cognito認証 |
| SG | 最小権限, RDS完全分離 |
| KMS | 年次自動ローテーション |

## トラブルシューティング

```bash
# Karpenter ログ
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter -f

# ALB Controller ログ
kubectl logs -n aws-load-balancer \
  -l app.kubernetes.io/name=aws-load-balancer-controller -f

# ArgoCD ログ
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server -f

# Pod Identity 動作確認
kubectl exec -n app <pod-name> -- \
  aws sts get-caller-identity

# DB接続確認
kubectl exec -n app <pod-name> -- \
  psql $DATABASE_URL -c "SELECT version();"
```

## コスト見積もり (ap-northeast-1, 最小構成)

| リソース | 月額概算 |
|---------|---------|
| EKS Control Plane | $73 |
| EC2 Workers (m6i.large x3, spot) | ~$80 |
| RDS Aurora Serverless v2 最小 | ~$100 |
| ALB | ~$20 |
| NAT Gateway x3 | ~$100 |
| EFS | ~$30 |
| WAF | ~$10 |
| **合計** | **~$413/月** |

> Karpenter で不要なノードを自動削除することでコスト最適化可能
