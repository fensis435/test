# EKSアプリケーション実行基盤 仕様書

**バージョン:** 1.0  
**作成日:** 2025年  
**対象環境:** AWS / Amazon EKS

---

## 本仕様書について

本仕様書は、AWS上に構築するコンテナアプリケーション実行基盤を定義する。要求仕様書と実装コード（CloudFormation・Kubernetes Manifest・CI/CD設定等）の中間成果物であり、実装者はこれを基準として環境構築およびアプリケーション配備を実施する。

本仕様書に記載されていない事項は実装者の独断では決定せず、設計レビューにて合意のうえ決定する。

---

# 目次

1. [システム構成](#1-システム構成)
2. [ネットワーク設計](#2-ネットワーク設計)
3. [EKSクラスタ設計](#3-eksクラスタ設計)
4. [CI/CD設計](#4-cicd設計)
5. [認証・認可設計](#5-認証認可設計)
6. [ストレージ設計](#6-ストレージ設計)
7. [監視・ロギング設計](#7-監視ロギング設計)
8. [セキュリティ設計](#8-セキュリティ設計)
9. [CloudFormation構成](#9-cloudformation構成)
10. [Kubernetes設計詳細](#10-kubernetes設計詳細)
11. [非機能要件](#11-非機能要件)
12. [命名規約](#12-命名規約)
13. [実装完了判定基準](#13-実装完了判定基準)

---

# 1. システム構成

## 1.1 全体アーキテクチャ

```
Internet
    │
    ▼
Route53（DNS解決）
    │
    ▼
ALB（TLS終端・WAF）
    │
    ▼
EKS Cluster
 ├─ System Node Group（Managed）
 │   ├─ ArgoCD
 │   ├─ Metrics Server
 │   ├─ EFS CSI Driver
 │   ├─ CloudWatch Agent
 │   └─ Karpenter
 │
 └─ Karpenter Node（動的プロビジョニング）
     └─ Application Pods

ECR ◄── CodeBuild（CI）

Secrets Manager / KMS / EFS / CloudWatch

Bastion EC2（kubectl / aws cli）
```

## 1.2 主要コンポーネント

| コンポーネント | 役割 | 備考 |
|---|---|---|
| EKS | コンテナオーケストレーション | Managed Control Plane |
| Karpenter | ワークロードノードの自動スケール | Spot優先、OnDemandフォールバック |
| ArgoCD | GitOpsベースのCD | Auto Sync / Self Heal |
| CodeBuild | コンテナイメージのCI | Git Push → Build → Scan → Push |
| ALB | 外部通信の入口 | WAF必須、HTTP→HTTPS強制 |
| EFS | 共有ストレージ | CSI Driverで連携 |
| Secrets Manager | シークレット管理 | KMS CMKで暗号化 |
| CloudWatch | 監視・ロギング | Container Insights有効 |

---

# 2. ネットワーク設計

## 2.1 基本方針

- AWSサービスとの通信はすべてVPC Endpoint（PrivateLink）経由とする
- NAT Gatewayへの依存を最小化する
- Podからの外部インターネット通信を原則禁止する
- インターネットアクセスを許可する通信は以下のみとする
  - ALB → Internet（外部公開）
  - Bastion → Internet（運用作業）
  - Cognito → Internet（認証基盤）
  - 必要時のOSパッケージ取得

## 2.2 VPC構成

### VPC

| 項目 | 値 |
|---|---|
| CIDR | 10.0.0.0/16 |

### サブネット

| 名称 | 用途 | 配置対象 |
|---|---|---|
| Public | 外部公開 | ALB、Bastion |
| Private-App | ワークロード | Karpenter Node |
| Private-System | システム管理 | Managed Node Group |
| Private-Endpoint | VPC通信 | VPC Endpoint |

## 2.3 VPC Endpoint

AWSサービスへの通信はすべて以下のEndpoint経由とする。

| サービス | 種別 |
|---|---|
| ECR API | Interface |
| ECR DKR | Interface |
| S3 | Gateway |
| CloudWatch Logs | Interface |
| CloudWatch Monitoring | Interface |
| STS | Interface |
| EKS | Interface |
| EC2 | Interface |
| Autoscaling | Interface |
| Secrets Manager | Interface |
| KMS | Interface |
| SSM | Interface |
| SSM Messages | Interface |
| EC2 Messages | Interface |

## 2.4 Security Group通信設計

### SG-ALB（インターネット → ALB）

| 送信元 | 送信先 | Port | 用途 |
|---|---|---|---|
| Internet | ALB | 443 | HTTPS受信 |
| Internet | ALB | 80 | HTTP受信（443へリダイレクト） |

### SG-SystemNode

| 送信元 | 送信先 | Port | 用途 |
|---|---|---|---|
| ALB | Node | 30000-32767 | NodePort |
| Node | EKS | 443 | API通信 |
| Node | VPC Endpoint | 443 | AWSサービス |
| Node | EFS | 2049 | ファイルマウント |

### SG-WorkloadNode

| 送信元 | 送信先 | Port | 用途 |
|---|---|---|---|
| ALB | Node | 30000-32767 | NodePort |
| Node | ECR Endpoint | 443 | イメージPull |
| Node | STS Endpoint | 443 | Pod Identity認証 |
| Node | Secrets Endpoint | 443 | シークレット取得 |
| Node | CloudWatch Endpoint | 443 | ログ・メトリクス送信 |
| Node | EFS | 2049 | ファイルマウント |

### SG-Bastion

| 送信元 | 送信先 | Port | 用途 |
|---|---|---|---|
| Admin IP | Bastion | 22 | SSH |
| Bastion | EKS API | 443 | kubectl |
| Bastion | VPC Endpoint | 443 | AWSサービス |

### SG-VpcEndpoint

| 送信元 | 送信先 | Port |
|---|---|---|
| System Node | Endpoint | 443 |
| Workload Node | Endpoint | 443 |
| Bastion | Endpoint | 443 |

### SG-EFS

| 送信元 | 送信先 | Port |
|---|---|---|
| System Node | EFS | 2049 |
| Workload Node | EFS | 2049 |

## 2.5 VPC Endpoint通信詳細

| Endpoint | 用途 | 利用者 |
|---|---|---|
| ECR API | イメージメタデータ取得 | CodeBuild、Kubelet、Container Runtime |
| ECR DKR | Docker Pull / Push | CodeBuild、Worker Node |
| STS | Pod Identity認証 | Application Pod、ArgoCD、CloudWatch Agent、EFS CSI Driver |
| Secrets Manager | シークレット取得 | Application Pod |
| KMS | データ復号 | Application Pod、Secrets Manager、EFS、CloudWatch Logs |
| CloudWatch Logs | ログ送信 | CloudWatch Agent |
| CloudWatch Monitoring | メトリクス送信 | CloudWatch Agent、Application |
| S3 | ECR内部通信、CodeBuild Artifact、CloudTrail | CodeBuild、ECR、CloudTrail |
| EKS | Cluster API通信 | Bastion、Node |
| EC2 | ノード管理（Karpenter） | Karpenter |
| AutoScaling | Managed Node Group管理 | EKS |

---

# 3. EKSクラスタ設計

## 3.1 Kubernetesバージョン

AWSがサポートする最新の安定バージョンを採用する（例：`1.33`）。  
マイナーバージョンアップグレードは年2回を目安に計画的に実施する。

## 3.2 ノード構成

### システムノード（Managed Node Group）

システムコンポーネント専用のノードグループ。アプリケーションPodの配置は禁止する。

| 項目 | 値 |
|---|---|
| 種別 | Managed Node Group |
| 台数（固定） | 2台 |
| 最小 | 2 |
| 最大 | 4 |
| ラベル | `node-role=system` |
| Taint | `node-role=system:NoSchedule` |

配置Pod：

- CoreDNS
- ArgoCD
- Karpenter
- Metrics Server
- CloudWatch Agent
- EFS CSI Driver

### ワークロードノード（Karpenter管理）

アプリケーションPod専用のノード。Karpenterが需要に応じて動的にプロビジョニングする。

| 項目 | 値 |
|---|---|
| 種別 | Karpenter動的プロビジョニング |
| ラベル | `node-role=workload` |
| キャパシティ | Spot優先、不足時OnDemand |
| AZ分散 | 最低2AZ |

## 3.3 Namespace設計

| Namespace | 用途 | ラベル例 |
|---|---|---|
| argocd | ArgoCDコンポーネント | owner: platform |
| kube-system | AWS Addon（VPC CNI等） | - |
| monitoring | CloudWatch Agent | owner: platform |
| karpenter | Karpenter | owner: platform |
| app-prod | 本番アプリケーション | environment: prod |
| app-stg | 検証アプリケーション | environment: stg |

Namespaceには以下のラベルを付与する。

```yaml
metadata:
  labels:
    owner: <team>
    environment: <env>
```

## 3.4 Karpenter設計

### EC2NodeClass

```yaml
apiVersion: karpenter.k8s.aws/v1
kind: EC2NodeClass
metadata:
  name: default-workload
spec:
  amiFamily: AL2023
  role: sample-prd-karpenter-node-role
  subnetSelectorTerms:
    - tags:
        karpenter.sh/discovery: sample-prd
  securityGroupSelectorTerms:
    - tags:
        karpenter.sh/discovery: sample-prd
  tags:
    Environment: prod
    System: sample
```

### NodePool — general（通常業務ワークロード）

```yaml
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: general
spec:
  template:
    metadata:
      labels:
        node-role: workload
    spec:
      nodeClassRef:
        name: default-workload
      requirements:
        - key: kubernetes.io/arch
          operator: In
          values: [amd64]
        - key: karpenter.sh/capacity-type
          operator: In
          values: [spot, on-demand]
        - key: node.kubernetes.io/instance-type
          operator: In
          values:
            - c6i.large
            - c6i.xlarge
            - m6i.large
            - m6i.xlarge
  disruption:
    consolidationPolicy: WhenEmptyOrUnderutilized
    expireAfter: 720h  # 30日毎に再作成
```

### NodePool — batch（バッチワークロード）

バッチ専用ノードにはTaintを付与し、一般Podの混在を防ぐ。

```yaml
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: batch
spec:
  template:
    metadata:
      labels:
        workload: batch
    spec:
      taints:
        - key: workload
          value: batch
          effect: NoSchedule
      nodeClassRef:
        name: default-workload
      requirements:
        - key: node.kubernetes.io/instance-type
          operator: In
          values:
            - c6i.2xlarge
            - c6i.4xlarge
```

### Karpenter運用ルール

| ルール | 設定値 |
|---|---|
| キャパシティタイプ | Spot優先、不足時OnDemand |
| AZ分散 | 最低2AZ |
| ノード寿命 | 720h（30日） |
| Consolidation | WhenEmptyOrUnderutilized |

### System Pod配置制御

System PodはManaged Node Groupへ固定配置するため、各Deploymentに以下を設定する。

```yaml
nodeSelector:
  node-role: system
```

## 3.5 Pod Identity

AWSリソースへのアクセスは**Pod Identityのみ**使用する。以下は禁止する。

| 禁止手段 | 理由 |
|---|---|
| IAM User / AccessKey | 静的クレデンシャルのリスク |
| IRSA（IAM Roles for Service Accounts） | 新規構築のためPod Identityに統一 |
| Kubernetes Secret（AWS認証情報） | 別途Secrets Manager参照 |

### Pod Identity Association一覧

| Namespace | ServiceAccount | IAM Role |
|---|---|---|
| argocd | argocd-server | ArgoCDRole |
| monitoring | cloudwatch-agent | CloudWatchAgentRole |
| kube-system | efs-csi-controller-sa | EFSRole |
| app-prod | app-sa | ApplicationRole |
| app-stg | app-sa | ApplicationRole |

CloudFormation定義例：

```yaml
AppPodIdentityAssociation:
  Type: AWS::EKS::PodIdentityAssociation
  Properties:
    ClusterName: !Ref ClusterName
    Namespace: app-prod
    ServiceAccount: app-sa
    RoleArn: !GetAtt ApplicationRole.Arn
```

> Pod Identity AssociationはCloudFormationで管理する。NamespaceおよびServiceAccount作成後に関連付けること。

---

# 4. CI/CD設計

## 4.1 CI（CodeBuild）

Git PushをトリガーにコンテナイメージをビルドしECRへプッシュする。

### CIフロー

```
Git Push
  ↓
CodeBuild
  ↓
Docker Build
  ↓
Unit Test
  ↓
Image Scan（ECR Enhanced Scanning）
  ↓
ECR Push
  ↓
GitOpsリポジトリ更新（イメージタグ更新）
```

### イメージタグ

| タグ | 内容 |
|---|---|
| `latest` | 最新ビルド |
| `git-sha` | コミットハッシュ |
| `version` | セマンティックバージョン |

### ECRリポジトリ命名例

```
app-prod
app-stg
```

## 4.2 CD（ArgoCD）

GitOpsリポジトリの状態をEKSクラスタへ継続的に同期する。

### CDフロー

```
Git Repository（GitOpsリポジトリ）
  ↓（Auto Sync）
ArgoCD
  ↓
EKS
```

### 同期設定

```yaml
syncPolicy:
  automated:
    prune: true
    selfHeal: true
  syncOptions:
    - CreateNamespace=true
```

| 設定 | 値 | 意味 |
|---|---|---|
| Auto Sync | Enabled | GitOpsリポジトリの変更を自動適用 |
| Self Heal | Enabled | クラスタとGitの差分を自動修復 |
| Prune | Enabled | Git上から削除されたリソースを自動削除 |

## 4.3 GitOps リポジトリ構成

```
gitops/
├─ applications/       # ArgoCD Application定義
├─ base/               # Kustomize base
│   ├─ api/
│   ├─ admin/
│   └─ batch/
└─ overlays/           # 環境ごとの差分
    ├─ dev/
    ├─ stg/
    └─ prod/
```

1つのArgoCD ApplicationはKubernetesの1サービスに対応する。

```
app-api     → API Service
app-admin   → Admin Service
app-batch   → Batch Service
```

## 4.4 ArgoCD Application定義例（APIサービス）

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: app-api
  namespace: argocd
spec:
  project: application
  source:
    repoURL: https://xxxxx.git
    targetRevision: main
    path: overlays/prod/api
  destination:
    server: https://kubernetes.default.svc
    namespace: app-prod
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

## 4.5 ArgoCD Project分離

| Project | 用途 |
|---|---|
| application | アプリケーション系 |
| platform | インフラ・基盤系 |
| monitoring | 監視系 |

---

# 5. 認証・認可設計

## 5.1 クラスタ管理者アクセス（Windows端末）

AWS IAM Identity Centerで認証後、以下のコマンドでkubeconfigを取得する。

```powershell
aws eks update-kubeconfig `
  --region ap-northeast-1 `
  --name eks-prod
```

## 5.2 Bastion EC2

踏み台EC2を経由してクラスタ操作を行う。

| 項目 | 内容 |
|---|---|
| 用途 | kubectl、helm、aws cli |
| アクセス方法 | SSM Session Manager または SSH（Admin IPのみ） |
| 配置 | Public Subnet |

## 5.3 アプリケーションログイン（Cognito）

ユーザ認証はCognitoで行い、セッション管理はアプリケーション側で実施する。

### 認証フロー

```
User
  ↓（ログイン）
Cognito（認証・JWT発行）
  ↓（JWT）
Application（JWT検証 → セッション発行）
```

| 役割 | 担当 |
|---|---|
| 認証（ID/PW検証） | Cognito |
| JWT発行 | Cognito |
| セッション管理 | Application |
| CognitoのセッションAPI | 利用しない |

## 5.4 ユーザ状態変更の検知

Cognitoのユーザ追加・削除・無効化をアプリケーションへリアルタイム通知する。

### 通知フロー

```
Cognito（ユーザ操作）
  ↓
CloudTrail（API呼び出し記録）
  ↓
EventBridge（イベントルーティング）
  ↓
Lambda（通知処理）
  ↓
Application API
```

### 通知対象イベント

- ユーザ追加
- ユーザ削除
- ユーザ無効化

---

# 6. ストレージ設計

## 6.1 EFS（共有ストレージ）

Podを跨いだファイル共有のために利用する。

| 項目 | 値 |
|---|---|
| 名称 | sample-prd-efs |
| Performance Mode | General Purpose |
| Throughput Mode | Elastic |
| 暗号化 | KMS CMK |

### Kubernetes連携

EFS CSI Driverを経由してPodへマウントする。

```yaml
# StorageClass
provisioner: efs.csi.aws.com
parameters:
  provisioningMode: efs-ap
```

Access Pointは用途ごとに分離する。

| Access Point | 用途 |
|---|---|
| app-upload | ファイルアップロード |
| app-share | アプリ間ファイル共有 |
| batch-work | バッチ作業領域 |

### 主な用途

- ファイル共有（複数Podからの同時アクセス）
- 添付ファイル保存
- バッチ連携データ

## 6.2 Secrets Manager

アプリケーションシークレットはKubernetes Secretを使用せず、Secrets Managerから取得する。

### 保存対象

- DBパスワード
- APIキー
- JWT署名鍵

### 命名規則

```
/<env>/<system>/<service>/<name>

例：/prod/sample/app/db-password
```

### ローテーション

| 対象 | 周期 |
|---|---|
| DBパスワード | 90日 |
| APIキー | 90日 |

### Kubernetes連携（Secrets Store CSI Driver）

```yaml
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: app-secret
spec:
  provider: aws
  parameters:
    objects: |
      - objectName: "/prod/sample/app/db-password"
        objectType: "secretsmanager"
```

Podへのマウント例：

```yaml
volumes:
  - name: secrets-store
    csi:
      driver: secrets-store.csi.k8s.io
      readOnly: true
      volumeAttributes:
        secretProviderClass: app-secret
```

## 6.3 暗号化

KMS CMK（カスタムマネージドキー）を全ストレージリソースに適用する。

| 対象リソース | KMS キー |
|---|---|
| EBS（Nodeのルートボリューム） | EksKmsKey |
| EFS | EfsKmsKey |
| Secrets Manager | SecretsKmsKey |
| CloudWatch Logs | LogsKmsKey |
| ECR | EksKmsKey |

---

# 7. 監視・ロギング設計

## 7.1 監視基盤

CloudWatchをメイン監視基盤として使用する。Container Insightsを有効化し、クラスタ全体の可観測性を確保する。

## 7.2 Container Insights

以下の粒度でメトリクスを収集する。

- Cluster
- Namespace
- Node
- Pod

## 7.3 ログ収集

| ログ種別 | 保存先 | LogGroup | 保持期間 |
|---|---|---|---|
| Application Log | CloudWatch Logs | /eks/prod/application | 365日 |
| Kubernetes System Log | CloudWatch Logs | /eks/prod/system | 365日 |
| Audit Log | CloudWatch Logs | /eks/prod/audit | 365日 |

全LogGroupはKMS CMKで暗号化する。

## 7.4 アラート設計

CloudWatch Alarmで以下の条件を監視し、SNSで通知する。

| 分類 | 監視対象 | 閾値 |
|---|---|---|
| Cluster | NodeNotReady | 1件以上 |
| Pod | CrashLoopBackOff | 1件以上 |
| Infrastructure | CPU使用率 | > 80% |
| Infrastructure | Memory使用率 | > 80% |
| Infrastructure | Disk使用率 | > 80% |
| Storage | EFS容量 | 閾値超過 |
| CI/CD | ArgoCD同期失敗 | 1件以上 |

## 7.5 ALB設計

AWS Load Balancer Controllerを使用してALBをプロビジョニングする。

| 項目 | 値 |
|---|---|
| Scheme | internet-facing |
| TLS証明書 | ACM |
| HTTP（80番） | 443へリダイレクト |
| WAF | 必須（AWS Managed Rules） |

---

# 8. セキュリティ設計

## 8.1 通信暗号化

全通信でTLS 1.2以上を使用する。

## 8.2 Kubernetes Secretの禁止

アプリケーションの機密情報を`kind: Secret`に格納することを禁止する。  
シークレット情報はすべてSecrets Managerから取得し、Secrets Store CSI Driverでマウントする。

```yaml
# ❌ 禁止
kind: Secret
```

## 8.3 コンテナイメージ管理

- イメージ取得元はECRのみ許可する
- DockerHub等の外部レジストリからの直接Pullは禁止する

## 8.4 イメージスキャン

ECR Enhanced Scanningを有効化し、CIパイプラインでスキャンを実施する。  
CRITICAL / HIGH の脆弱性を含むイメージはデプロイを禁止する。

## 8.5 IAM権限マトリクス

### ロール一覧

| ロール | 利用主体 |
|---|---|
| EksClusterRole | EKS Control Plane |
| ManagedNodeRole | Managed Node Group |
| KarpenterNodeRole | Karpenter Node |
| ApplicationRole | Application Pod |
| CloudWatchAgentRole | CloudWatch Agent |
| ArgoCDRole | ArgoCD |
| CodeBuildRole | CodeBuild |
| EFSRole | EFS CSI Driver |

### ApplicationRole（最小権限）

**許可：**

| サービス | Action |
|---|---|
| Secrets Manager | GetSecretValue |
| KMS | Decrypt |
| CloudWatch | PutMetricData |

**禁止：**

- IAM（ロール・ポリシー操作）
- EC2（インスタンス操作）
- EKS（クラスタ操作）
- KMS管理操作（CreateKey等）

### CloudWatchAgentRole

| サービス | Action |
|---|---|
| CloudWatch Logs | CreateLogStream、PutLogEvents |
| CloudWatch | PutMetricData |

### EFS CSI Role

| サービス | Action |
|---|---|
| Elastic File System | DescribeFileSystems、DescribeMountTargets |

### ArgoCDRole

| サービス | Action |
|---|---|
| ECR | BatchGetImage、GetAuthorizationToken |
| STS | AssumeRole |

### CodeBuildRole

| サービス | Action |
|---|---|
| ECR | Push / Pull |
| CloudWatch Logs | Write |
| S3 | Read / Write |
| Secrets Manager | Read |

---

# 9. CloudFormation構成

## 9.1 管理方針

AWSリソースはすべてCloudFormationで構築・管理する。

**CloudFormation管理対象：**

VPC、VPC Endpoint、EKS、Managed Node Group、EFS、KMS、Secrets Manager、EventBridge、Lambda、CloudWatch、IAM、CloudTrail、Cognito、ECR、CodeBuild、CodePipeline

**Kubernetes Manifest管理対象（CloudFormation対象外）：**

Namespace、Deployment、Service、Ingress、ArgoCD Application、Karpenter NodePool / EC2NodeClass、Pod Identity Association

## 9.2 スタック構成と依存関係

```
01-network       VPC / Subnet / Route / SG / VPC Endpoint / ALB
    ↓
02-security      KMS / IAM / Pod Identity Role / CloudTrail
    ↓
03-storage       EFS / Backup / Secrets Manager
    ↓
04-eks           EKS Cluster / Managed Node Group / Addon / Pod Identity
    ↓
05-monitoring    CloudWatch / LogGroup / Alarm / SNS
    ↓
06-cicd          CodeBuild / CodePipeline / ECR
    
07-identity      Cognito / Lambda / EventBridge（依存なし・独立デプロイ可）
```

## 9.3 スタック詳細

### 01-network

| リソース | Logical ID | Type |
|---|---|---|
| VPC | Vpc | AWS::EC2::VPC |
| Public Subnet（AZ1/2） | PublicSubnetAz1/2 | AWS::EC2::Subnet |
| Private System Subnet（AZ1/2） | PrivateSystemSubnetAz1/2 | AWS::EC2::Subnet |
| Private App Subnet（AZ1/2） | PrivateAppSubnetAz1/2 | AWS::EC2::Subnet |
| Internet Gateway | InternetGateway | AWS::EC2::InternetGateway |
| NAT Gateway（AZ1/2） | NatGatewayAz1/2 | AWS::EC2::NatGateway |
| ALB | ApplicationLoadBalancer | AWS::ElasticLoadBalancingV2::LoadBalancer |
| HTTPS Listener | AlbHttpsListener | AWS::ElasticLoadBalancingV2::Listener |
| HTTP Listener | AlbHttpListener | AWS::ElasticLoadBalancingV2::Listener |

**Interface Endpoints：**

| Logical ID | サービス |
|---|---|
| EcrApiEndpoint | ecr.api |
| EcrDkrEndpoint | ecr.dkr |
| EksEndpoint | eks |
| Ec2Endpoint | ec2 |
| StsEndpoint | sts |
| SecretsManagerEndpoint | secretsmanager |
| KmsEndpoint | kms |
| LogsEndpoint | logs |
| MonitoringEndpoint | monitoring |
| SsmEndpoint | ssm |
| SsmMessagesEndpoint | ssmmessages |
| Ec2MessagesEndpoint | ec2messages |

**Gateway Endpoints：**

| Logical ID | サービス |
|---|---|
| S3Endpoint | s3 |

### 02-security

| リソース | Logical ID |
|---|---|
| EKS用KMSキー | EksKmsKey |
| EFS用KMSキー | EfsKmsKey |
| Logs用KMSキー | LogsKmsKey |
| Secrets用KMSキー | SecretsKmsKey |
| EKS Cluster Role | EksClusterRole |
| Managed Node Role | ManagedNodeRole |
| Karpenter Node Role | KarpenterNodeRole |
| CodeBuild Role | CodeBuildRole |
| ArgoCD Role | ArgoCdRole |
| CloudWatch Agent Role | CloudWatchAgentRole |
| Application Role | ApplicationRole |
| EFS CSI Role | EfsCsiRole |
| CloudTrail | OrganizationTrail |

### 03-storage

| リソース | Logical ID |
|---|---|
| EFS FileSystem | ApplicationEfs |
| EFS Mount Target AZ1/2 | ApplicationEfsMountTargetAz1/2 |
| DB Password Secret | DbPasswordSecret |
| JWT Secret | JwtSecret |
| API Key Secret | ApiKeySecret |

### 04-eks

| リソース | Logical ID |
|---|---|
| EKS Cluster | EksCluster |
| System Node Group | SystemNodeGroup |
| VPC CNI Addon | VpcCniAddon |
| CoreDNS Addon | CoreDnsAddon |
| Kube Proxy Addon | KubeProxyAddon |
| Pod Identity Addon | PodIdentityAddon |

### 05-monitoring

CloudWatch LogGroup、Alarm、SNS Topic

### 06-cicd

| リソース | Logical ID |
|---|---|
| ECR Repository | ApplicationRepository |
| CodeBuild Project | ApplicationBuildProject |
| CodePipeline | ApplicationPipeline |

### 07-identity

Cognito UserPool、Lambda（ユーザ変更通知）、EventBridge Rule

## 9.4 パラメータ設計

環境差異はCloudFormation Parameterで吸収する。

```yaml
Parameters:
  Environment:
    Type: String
    AllowedValues: [dev, stg, prd]

  VpcCidr:
    Type: String
    Default: 10.0.0.0/16

  ClusterName:
    Type: String
```

## 9.5 スタック間の値連携（Export/Import）

```yaml
# 出力側（01-network）
Outputs:
  VpcId:
    Value: !Ref Vpc
    Export:
      Name: !Sub "${AWS::StackName}-vpc-id"

# 参照側（04-eks）
VpcId: !ImportValue "sample-prd-network-vpc-id"
```

## 9.6 ディレクトリ構成

```
infra/
└─ templates/
    ├─ 01-network/
    │   ├─ vpc.yaml
    │   ├─ subnet.yaml
    │   ├─ route.yaml
    │   ├─ alb.yaml
    │   └─ vpce.yaml
    ├─ 02-security/
    │   ├─ kms.yaml
    │   ├─ iam.yaml
    │   └─ cloudtrail.yaml
    ├─ 03-storage/
    │   ├─ efs.yaml
    │   ├─ backup.yaml
    │   └─ secrets.yaml
    ├─ 04-eks/
    │   ├─ cluster.yaml
    │   ├─ managed-nodegroup.yaml
    │   ├─ addons.yaml
    │   └─ pod-identity.yaml
    ├─ 05-monitoring/
    │   ├─ cloudwatch.yaml
    │   ├─ alarms.yaml
    │   └─ sns.yaml
    ├─ 06-cicd/
    │   ├─ ecr.yaml
    │   ├─ codebuild.yaml
    │   └─ codepipeline.yaml
    └─ 07-identity/
        ├─ cognito.yaml
        ├─ lambda.yaml
        └─ eventbridge.yaml
```

---

# 10. Kubernetes設計詳細

## 10.1 Deployment標準設定

全Deploymentに以下のリソース制限を必須とする。

```yaml
resources:
  requests:
    cpu: 250m
    memory: 512Mi
  limits:
    cpu: 1000m
    memory: 1024Mi
```

## 10.2 PodDisruptionBudget

全サービスにPDBを設定し、ローリングアップデートやノード退避時の可用性を担保する。

```yaml
spec:
  minAvailable: 1
```

## 10.3 HorizontalPodAutoscaler

全APIサービスにHPAを設定する。

```yaml
spec:
  minReplicas: 2
  maxReplicas: 10
  targetCPUUtilizationPercentage: 70
```

## 10.4 Kubernetes Manifest標準

### Namespace

```yaml
metadata:
  labels:
    environment: prod
    owner: application
```

---

# 11. 非機能要件

| 分類 | 項目 | 要件 |
|---|---|---|
| 可用性 | 構成 | マルチAZ |
| 可用性 | RTO（復旧目標時間） | 4時間以内 |
| 可用性 | RPO（データ損失許容） | 1時間以内 |
| セキュリティ | 通信暗号化 | TLS 1.2以上 |
| セキュリティ | 保存データ暗号化 | 全保存データをKMS CMKで暗号化 |
| セキュリティ | 認証 | Cognito（アプリ）/ IAM Identity Center（管理） |
| セキュリティ | 権限管理 | IAM Role最小権限の原則 |
| 監査 | ログ保持期間 | 365日 |
| CI/CD | コンテナ配備 | ArgoCD（GitOps） |
| CI/CD | CI | CodeBuild |
| CI/CD | CD | ArgoCD |
| インフラ | コンテナレジストリ | ECR |
| インフラ | 共有ストレージ | EFS |

---

# 12. 命名規約

## 12.1 AWSリソース命名

```
<system>-<env>-<resource>
```

例：

```
sample-prd-vpc
sample-prd-eks
sample-prd-ecr
sample-prd-efs
```

## 12.2 環境識別子

| 環境 | 識別子 |
|---|---|
| 開発 | dev |
| 検証 | stg |
| 本番 | prd |

## 12.3 Secrets Manager命名

```
/<env>/<system>/<service>/<name>

例：/prod/sample/app/db-password
```

## 12.4 CloudWatch LogGroup命名

```
/eks/<env>/application
/eks/<env>/system
/eks/<env>/audit
```

## 12.5 必須タグ

全AWSリソースに以下のタグを付与する。

| Key | Value例 |
|---|---|
| System | sample |
| Environment | prd |
| ManagedBy | CloudFormation |
| Owner | platform-team |
| CostCenter | xxxx |

---

# 13. 実装完了判定基準

以下の全項目を確認した時点で実装完了とする。

## 基盤

- [ ] VPC・Subnet・Endpoint 作成完了
- [ ] EKS Cluster 作成完了
- [ ] Managed Node Group 起動確認
- [ ] Pod Identity 有効化確認

## CI/CD

- [ ] CodeBuild ビルド成功
- [ ] ECR へのイメージPush成功
- [ ] ArgoCD による自動同期成功

## アプリケーション

- [ ] Application Pod 起動成功
- [ ] Secrets Manager からのシークレット取得成功
- [ ] EFS マウント成功

## 監視

- [ ] Container Insights 有効化確認
- [ ] CloudWatch Logs へのログ出力確認
- [ ] アラーム通知確認（SNS）

## セキュリティ

- [ ] 全ストレージの KMS CMK 暗号化確認
- [ ] Secrets Manager 経由のシークレット利用確認
- [ ] Endpoint 経由の通信確認（直接インターネット通信なし）
- [ ] ECR Enhanced Scanning 有効化確認

---

## 付録：主要運用コマンド

### kubeconfig取得

```powershell
aws eks update-kubeconfig `
  --name sample-prd-eks `
  --region ap-northeast-1
```

### Pod確認

```powershell
kubectl get pods -A
```

### ArgoCD Application確認

```powershell
kubectl get applications -n argocd
```
