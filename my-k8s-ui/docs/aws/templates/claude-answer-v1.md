
以下を作成する実務で使えるcloudformationテンプレート+bash scriptを作って。(つまり自動化)
 - AWS EKS+E2C worker
 - Route53, WAF, SG, ALBを使う。
 - PodはPVにEBSとEFSを使う。
 - PodはDBMSとしてRDS for postgresqlを使う。
 - KMSで暗号化をする。
 - kerpenterがEC2 Workerを動的にスケールする。
 - Webサーバはログインのユーザ管理とJWT認証の仕組みだけをCogniteで使う。
 - EKS Pod Identityを使う。
 - これらのIAMロールと適用を行う。
 - Helm + GitOps(ArgoCD)を使う。
 - NAT Gatewayを使う。
 - VPC Endpoints
 - CloudWatchを使う。
 - Secrets Managerを使う。
---
---

まず、必要なスキルファイルを確認してから、包括的なCloudFormationテンプレートとBashスクリプトを作成します。では、各コンポーネントを順番に作成していきます。合計4,220行のプロダクションレディなインフラコードを生成しました。構成は以下の通りです。

---

## 生成ファイル一覧

| ファイル | 内容 |
|---------|------|
| `scripts/deploy.sh` | メイン自動化スクリプト (843行) |
| `cloudformation/01-base.yaml` | VPC・3AZ NAT・KMS×4キー・Cognito・ACM |
| `cloudformation/02-security.yaml` | SG (ALB/EKS/RDS/EFS) + WAF v2 マネージドルール |
| `cloudformation/03-iam.yaml` | IAM: EKS/Node/Karpenter/EBS-CSI/EFS-CSI/ALB/ArgoCD + Karpenter SQS/EventBridge |
| `cloudformation/04-eks-rds-efs.yaml` | EKSクラスター・Pod Identity Addon・Karpenter用NodeGroup・EFS・Aurora PostgreSQL |
| `helm/app-values.yaml` | アプリHelmバリューテンプレート |
| `argocd/applications.yaml` | App-of-Appsパターン + AppProject定義 |
| `argocd/k8s-manifests.yaml` | Deployment/HPA/PDB/NetworkPolicy/ExternalSecret/PVC |

---

## デプロイ方法（最小手順）

```bash
export PROJECT_NAME="myapp"
export ENVIRONMENT="prod"
export AWS_REGION="ap-northeast-1"
export DOMAIN_NAME="myapp.example.com"
export HOSTED_ZONE_ID="Z1234567890ABC"
export ARGOCD_REPO_URL="https://github.com/org/repo"

./scripts/deploy.sh deploy
```

---

## 主要な実装ポイント

**Pod Identity** — IRSAと違いアノテーション不要。`pods.eks.amazonaws.com`へのTrust PolicyとEKS側のAssociation APIで完結。

**Karpenter** — Karpenter用のNodeGroupを先に作り（bootstrap）、その後KarpenterがEC2を動的に管理。Spot中断はSQS + EventBridgeで自動ハンドリング。

**KMS** — EKS Secrets / RDS / EBS / EFSそれぞれ独立したキーで管理し年次ローテーション有効。

**Cognito** — ALBレベルでJWT認証を実装（`alb.ingress.kubernetes.io/auth-type: cognito`）。アプリはX-Amzn-Oidc-Dataヘッダーでユーザー情報を受け取るだけ。

**ExternalSecrets** — Secrets ManagerからDB認証情報とCognito設定をKubernetes Secretに同期。Pod Identityで認証。