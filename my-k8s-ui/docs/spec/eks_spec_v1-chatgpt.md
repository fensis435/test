# EKSアプリケーション実行基盤 仕様書

## 1. 本仕様書の目的

本仕様書は、AWS上に構築するコンテナアプリケーション実行基盤について定義する。

本仕様書は要求仕様書と実装コード（CloudFormation、Kubernetes Manifest、CI/CD設定等）の中間成果物であり、実装者は本仕様書を基準として環境構築およびアプリケーション配備を実施する。

本仕様書に記載されていない内容は実装者判断とせず、設計レビューにて決定するものとする。

---

# 2. システム構成

## 2.1 全体構成

```text
Internet
    │
    ▼
Route53
    │
    ▼
ALB
    │
    ▼
EKS Cluster
 ├─ System Node Group
 │   ├─ ArgoCD
 │   ├─ Metrics Server
 │   ├─ EFS CSI Driver
 │   ├─ CloudWatch Agent
 │   └─ Karpenter
 │
 └─ Karpenter Node
     └─ Application Pods

ECR
 ▲
 │
CodeBuild

Secrets Manager
KMS
EFS
CloudWatch

Bastion EC2
  └─ kubectl / aws cli
```

---

# 3. ネットワーク設計

## 3.1 基本方針

以下を原則とする。

* AWSサービスとの通信はVPC Endpointを利用する
* NAT Gateway依存を最小化する
* Podからの外部通信を制限する
* AWS内部通信はPrivateLink経由とする

---

## 3.2 VPC構成

### VPC

| 項目   | 値           |
| ---- | ----------- |
| CIDR | 10.0.0.0/16 |

---

### サブネット

| 用途               | 配置                 |
| ---------------- | ------------------ |
| Public           | ALB、Bastion        |
| Private-App      | Karpenter Node     |
| Private-System   | Managed Node Group |
| Private-Endpoint | VPC Endpoint       |

---

## 3.3 VPC Endpoint

以下を必須とする。

| サービス                  | Endpoint  |
| --------------------- | --------- |
| ECR API               | Interface |
| ECR DKR               | Interface |
| S3                    | Gateway   |
| CloudWatch Logs       | Interface |
| CloudWatch Monitoring | Interface |
| STS                   | Interface |
| EKS                   | Interface |
| EC2                   | Interface |
| Autoscaling           | Interface |
| Secrets Manager       | Interface |
| KMS                   | Interface |
| SSM                   | Interface |
| SSM Messages          | Interface |
| EC2 Messages          | Interface |

---

## 3.4 インターネット接続

以下のみ許可する。

* ALB → Internet
* Bastion → Internet
* Cognito → Internet
* 必要時のOSパッケージ取得

その他通信はVPC Endpoint経由とする。

---

# 4. EKSクラスタ設計

## 4.1 Kubernetes Version

最新のAWSサポート版を採用する。

例

```text
1.33
```

---

## 4.2 ノード構成

### システムノード

Managed Node Groupを利用する。

用途

* ArgoCD
* Karpenter
* EFS CSI Driver
* CloudWatch Agent
* CoreDNS
* Metrics Server

固定台数

```text
2台
```

最小

```text
2
```

最大

```text
4
```

---

### ワークロードノード

Karpenterで管理する。

用途

* アプリケーションPod

特徴

* 自動スケール
* Spot優先
* 不足時OnDemand

---

## 4.3 Pod Identity

IAM Role for Service Accountは利用しない。

全てのAWSアクセスはPod Identityを利用する。

対象

* ArgoCD
* EFS CSI Driver
* CloudWatch Agent
* アプリケーション

---

# 5. CI/CD設計

## 5.1 CI

CodeBuildを利用する。

---

### 処理フロー

```text
Git Push

↓
CodeBuild

↓
Docker Build

↓
Image Scan

↓
ECR Push

↓
GitOps Repository更新
```

---

### コンテナ格納先

ECR

命名例

```text
app-prod
app-stg
```

---

## 5.2 CD

ArgoCDを利用する。

---

### デプロイ方式

GitOps

```text
Git Repository
      ↓
ArgoCD
      ↓
EKS
```

---

### 同期方式

Auto Sync

```text
Enabled
```

---

### Self Heal

```text
Enabled
```

---

# 6. 認証・認可設計

## 6.1 管理者アクセス

### Windows端末

前提

* AWS IAM Identity Center認証済
* PowerShell利用可能

実行例

```powershell
aws eks update-kubeconfig `
 --region ap-northeast-1 `
 --name eks-prod
```

---

## 6.2 Bastion

踏み台EC2を配置する。

利用用途

* kubectl
* helm
* aws cli

---

## 6.3 アプリログイン

認証基盤

認証のみCognitoを利用する。

---

### 認証フロー

```text
User

↓
Cognito Login

↓
JWT発行

↓
Application

↓
Session発行
```

---

### セッション管理

アプリケーションが管理する。

Cognitoは利用しない。

---

## 6.4 ユーザ追加・削除検知

アプリはユーザ状態変更を認識する必要がある。

実現方式

```text
Cognito
 ↓
CloudTrail
 ↓
EventBridge
 ↓
Lambda
 ↓
Application API
```

通知対象

* ユーザ追加
* ユーザ削除
* ユーザ無効化

---

# 7. ストレージ設計

## 7.1 EFS

共有ストレージとして利用する。

---

### 用途

* ファイル共有
* 添付ファイル
* バッチ連携

---

### Kubernetes連携

EFS CSI Driver

---

### PersistentVolume

```yaml
StorageClass:
  efs-sc
```

---

## 7.2 Secrets

Secrets Managerを利用する。

保存対象

* DBパスワード
* APIキー
* JWT署名鍵

---

### Kubernetes連携

Secrets Store CSI Driver

---

## 7.3 暗号化

KMS CMKを利用する。

対象

* EBS
* EFS
* Secrets Manager
* CloudWatch Logs
* ECR

---

# 8. 監視・ロギング設計

## 8.1 監視基盤

CloudWatchを利用する。

---

## 8.2 Container Insights

有効化する。

取得対象

* Node
* Pod
* Namespace
* Cluster

---

## 8.3 ログ

収集対象

* Application Log
* Kubernetes Log
* Audit Log

---

保存先

```text
CloudWatch Logs
```

---

保持期間

```text
365日
```

---

## 8.4 アラート

CloudWatch Alarm

対象

* Node障害
* Pod再起動異常
* CPU高騰
* Memory高騰
* EFS容量閾値
* ArgoCD同期失敗

---

# 9. セキュリティ設計

## 9.1 通信暗号化

全通信TLS1.2以上

---

## 9.2 Kubernetes Secret

利用禁止

以下を禁止する。

```yaml
kind: Secret
```

アプリ機密情報はSecrets Managerから取得する。

---

## 9.3 イメージ管理

ECRのみ利用可能。

DockerHubからの直接Pullは禁止。

---

## 9.4 イメージスキャン

ECR Enhanced Scanningを有効化する。

重大脆弱性を含むイメージはデプロイ禁止。

---

# 10. CloudFormation適用方針

## 10.1 原則

AWSリソースはCloudFormationで構築する。

対象

* VPC
* Endpoint
* EKS
* Node Group
* EFS
* KMS
* Secrets Manager
* EventBridge
* Lambda
* CloudWatch

---

## 10.2 CloudFormation対象外

以下はKubernetes Manifest管理とする。

* Namespace
* Deployment
* Service
* Ingress
* ArgoCD Application
* Karpenter NodePool
* Pod Identity Association

---

# 11. 非機能要件

| 項目         | 要件           |
| ---------- | ------------ |
| 可用性        | マルチAZ        |
| 復旧目標(RTO)  | 4時間以内        |
| データ損失(RPO) | 1時間以内        |
| 監査ログ保持     | 365日         |
| 暗号化        | 全保存データ       |
| 認証         | Cognito      |
| 権限管理       | IAM Role最小権限 |
| コンテナ配備     | ArgoCD       |
| CI         | CodeBuild    |
| CD         | ArgoCD       |
| コンテナ保管     | ECR          |
| 共有ストレージ    | EFS          |

---

# 12. リソース命名規約

## 12.1 命名形式

AWSリソースは以下形式で統一する。

```text
<system>-<env>-<resource>
```

例

```text
sample-prd-vpc
sample-prd-eks
sample-prd-ecr
sample-prd-efs
```

---

## 12.2 環境識別子

| 環境 | 識別子 |
| -- | --- |
| 開発 | dev |
| 検証 | stg |
| 本番 | prd |

---

## 12.3 タグ

全リソースへ付与する。

| Key         | Value例         |
| ----------- | -------------- |
| System      | sample         |
| Environment | prd            |
| ManagedBy   | CloudFormation |
| Owner       | platform-team  |
| CostCenter  | xxxx           |

---

# 13. CloudFormationスタック分割方針

## 13.1 スタック構成

スタックは以下単位で分離する。

```text
01-network
02-security
03-storage
04-eks
05-monitoring
06-cicd
07-identity
```

---

## 13.2 依存関係

```text
01-network
    ↓
02-security
    ↓
03-storage
    ↓
04-eks
    ↓
05-monitoring
    ↓
06-cicd
```

---

## 13.3 スタック内容

### 01-network

対象

```text
VPC
Subnet
RouteTable
NACL
SecurityGroup
VPC Endpoint
ALB
```

---

### 02-security

対象

```text
KMS
IAM
Pod Identity Role
CloudTrail
```

---

### 03-storage

対象

```text
EFS
Backup
SecretsManager
```

---

### 04-eks

対象

```text
EKS Cluster
Managed Node Group
OIDC
Pod Identity
```

---

### 05-monitoring

対象

```text
CloudWatch
LogGroup
Alarm
SNS
```

---

### 06-cicd

対象

```text
CodeBuild
CodePipeline
ECR
```

---

### 07-identity

対象

```text
Cognito
Lambda
EventBridge
```

---

# 14. EKS Namespace設計

## Namespace一覧

| Namespace   | 用途               |
| ----------- | ---------------- |
| argocd      | ArgoCD           |
| kube-system | AWS Addon        |
| monitoring  | CloudWatch Agent |
| karpenter   | Karpenter        |
| app-prod    | 本番アプリ            |
| app-stg     | 検証アプリ            |

---

## ラベル

例

```yaml
metadata:
  labels:
    owner: application
    environment: prod
```

---

# 15. Node設計

## 15.1 Managed Node Group

用途

```text
システム管理Pod専用
```

配置Pod

```text
CoreDNS
ArgoCD
Karpenter
Metrics Server
CloudWatch Agent
EFS CSI Driver
```

---

ラベル

```yaml
node-role=system
```

---

Taint

```yaml
node-role=system:NoSchedule
```

---

アプリケーションPodは配置禁止。

---

## 15.2 Karpenter

用途

```text
アプリケーションPod専用
```

ラベル

```yaml
node-role=workload
```

---

# 16. Karpenter設計

## EC2NodeClass

名称

```text
default-workload
```

---

AMI

```text
AL2023
```

---

IAM Role

```text
sample-prd-karpenter-node-role
```

---

Subnet

```text
private-app
```

---

Security Group

```text
sample-prd-worker-sg
```

---

## NodePool

### general

用途

```text
通常アプリ
```

インスタンス

```yaml
c6i.large
c6i.xlarge
m6i.large
m6i.xlarge
```

---

Capacity Type

```yaml
spot
on-demand
```

---

Weight

```yaml
100
```

---

### batch

用途

```text
バッチ
```

インスタンス

```yaml
c6i.2xlarge
c6i.4xlarge
```

---

Taint

```yaml
workload=batch
```

---

## Consolidation

有効

```yaml
consolidationPolicy: WhenEmptyOrUnderutilized
```

---

## Expire

```yaml
expireAfter: 720h
```

---

# 17. Pod Identity設計

## 基本方針

AWS APIアクセスはPod Identityのみ利用する。

以下は禁止。

```text
IAM User
AccessKey
IRSA
```

※IRSAを禁止するかは議論の余地があります。新規構築であればPod Identityへ統一する方針として記載。

---

## Pod Identity対応表

| Namespace   | ServiceAccount        | IAM Role        |
| ----------- | --------------------- | --------------- |
| argocd      | argocd-server         | ArgoCDRole      |
| monitoring  | cloudwatch-agent      | CloudWatchRole  |
| kube-system | efs-csi-controller-sa | EFSRole         |
| app-prod    | app-sa                | ApplicationRole |

---

## ApplicationRole

許可例

```json
{
  "Version":"2012-10-17",
  "Statement":[
    {
      "Effect":"Allow",
      "Action":[
        "secretsmanager:GetSecretValue"
      ],
      "Resource":"*"
    }
  ]
}
```

---

# 18. EFS設計

## FileSystem

名称

```text
sample-prd-efs
```

---

Performance Mode

```text
General Purpose
```

---

Throughput

```text
Elastic
```

---

暗号化

```text
KMS CMK
```

---

## StorageClass

```yaml
provisioningMode: efs-ap
```

---

Access Point

用途ごとに分離する。

例

```text
app-upload
app-share
batch-work
```

---

# 19. Secrets Manager設計

## 命名規則

```text
/<env>/<system>/<service>/<name>
```

例

```text
/prod/sample/app/db-password
```

---

## ローテーション

対象

```text
DB Password
API Key
```

---

周期

```text
90日
```

---

# 20. ALB設計

## Ingress Controller

AWS Load Balancer Controllerを利用する。

---

## ALB

Scheme

```text
internet-facing
```

---

TLS

```text
ACM
```

---

HTTP

```text
443へリダイレクト
```

---

WAF

必須

```text
AWS Managed Rules
```

---

# 21. CloudWatch設計

## LogGroup

命名

```text
/eks/prod/application
/eks/prod/system
```

---

保持期間

```text
365日
```

---

暗号化

```text
KMS
```

---

## Alarm

### Cluster

```text
NodeNotReady
```

---

### Pod

```text
CrashLoopBackOff
```

---

### Infrastructure

```text
CPU > 80%
Memory > 80%
Disk > 80%
```

---

# 22. GitOps設計

## Repository構成

```text
gitops
├─ base
├─ overlays
│  ├─ dev
│  ├─ stg
│  └─ prod
└─ argocd
```

---

## ArgoCD Application

```text
1 Application = 1 Service
```

---

例

```text
app-api
app-batch
app-admin
```

---

## Sync Policy

```yaml
automated:
  prune: true
  selfHeal: true
```

---

# 23. CodeBuild設計

## buildspec

処理順

```text
Docker Build
↓
Unit Test
↓
Image Scan
↓
ECR Push
↓
GitOps更新
```

---

タグ

```text
latest
git-sha
version
```

---

# 24. 運用コマンド

## kubeconfig取得

```powershell
aws eks update-kubeconfig `
 --name sample-prd-eks `
 --region ap-northeast-1
```

---

## Pod確認

```powershell
kubectl get pods -A
```

---

## ArgoCD確認

```powershell
kubectl get applications -A
```

---

# 25. CloudFormationリソース一覧

## 25.1 01-network

### VPC

| Logical ID | Resource Type |
| ---------- | ------------- |
| Vpc        | AWS::EC2::VPC |

---

### Subnet

| Logical ID             | Resource Type    |
| ---------------------- | ---------------- |
| PublicSubnetAz1        | AWS::EC2::Subnet |
| PublicSubnetAz2        | AWS::EC2::Subnet |
| PrivateSystemSubnetAz1 | AWS::EC2::Subnet |
| PrivateSystemSubnetAz2 | AWS::EC2::Subnet |
| PrivateAppSubnetAz1    | AWS::EC2::Subnet |
| PrivateAppSubnetAz2    | AWS::EC2::Subnet |

---

### RouteTable

| Logical ID              |
| ----------------------- |
| PublicRouteTable        |
| PrivateSystemRouteTable |
| PrivateAppRouteTable    |

---

### Internet Gateway

| Logical ID                |
| ------------------------- |
| InternetGateway           |
| InternetGatewayAttachment |

---

### NAT Gateway

| Logical ID    |
| ------------- |
| NatGatewayAz1 |
| NatGatewayAz2 |

---

### ALB

| Logical ID              |
| ----------------------- |
| ApplicationLoadBalancer |
| AlbHttpsListener        |
| AlbHttpListener         |

---

# 25.2 VPC Endpoint

## Interface Endpoint

| Logical ID             | Service        |
| ---------------------- | -------------- |
| EcrApiEndpoint         | ecr.api        |
| EcrDkrEndpoint         | ecr.dkr        |
| EksEndpoint            | eks            |
| Ec2Endpoint            | ec2            |
| StsEndpoint            | sts            |
| SecretsManagerEndpoint | secretsmanager |
| KmsEndpoint            | kms            |
| LogsEndpoint           | logs           |
| MonitoringEndpoint     | monitoring     |
| SsmEndpoint            | ssm            |
| SsmMessagesEndpoint    | ssmmessages    |
| Ec2MessagesEndpoint    | ec2messages    |

---

## Gateway Endpoint

| Logical ID | Service |
| ---------- | ------- |
| S3Endpoint | s3      |

---

# 25.3 02-security

## KMS

| Logical ID    |
| ------------- |
| EksKmsKey     |
| EfsKmsKey     |
| LogsKmsKey    |
| SecretsKmsKey |

---

## IAM

| Logical ID          |
| ------------------- |
| EksClusterRole      |
| ManagedNodeRole     |
| KarpenterNodeRole   |
| CodeBuildRole       |
| ArgoCdRole          |
| CloudWatchAgentRole |
| ApplicationRole     |
| EfsCsiRole          |

---

## CloudTrail

| Logical ID        |
| ----------------- |
| OrganizationTrail |
| CloudTrailBucket  |

---

# 25.4 03-storage

## EFS

| Logical ID                   |
| ---------------------------- |
| ApplicationEfs               |
| ApplicationEfsMountTargetAz1 |
| ApplicationEfsMountTargetAz2 |

---

## Secrets

| Logical ID       |
| ---------------- |
| DbPasswordSecret |
| JwtSecret        |
| ApiKeySecret     |

---

# 25.5 04-eks

## Cluster

| Logical ID |
| ---------- |
| EksCluster |

---

## Managed Node Group

| Logical ID      |
| --------------- |
| SystemNodeGroup |

---

## Addons

| Logical ID       |
| ---------------- |
| VpcCniAddon      |
| CoreDnsAddon     |
| KubeProxyAddon   |
| PodIdentityAddon |

---

# 25.6 06-cicd

## ECR

| Logical ID            |
| --------------------- |
| ApplicationRepository |

---

## CodeBuild

| Logical ID              |
| ----------------------- |
| ApplicationBuildProject |

---

# 26. IAM権限マトリクス

## Role一覧

| Role                | 利用主体             |
| ------------------- | ---------------- |
| EksClusterRole      | EKS              |
| ManagedNodeRole     | Managed Node     |
| KarpenterNodeRole   | Karpenter Node   |
| ApplicationRole     | Application Pod  |
| CloudWatchAgentRole | CloudWatch Agent |
| ArgoCdRole          | ArgoCD           |
| CodeBuildRole       | CodeBuild        |

---

## ApplicationRole

### 許可

| Service        | Action         |
| -------------- | -------------- |
| SecretsManager | GetSecretValue |
| KMS            | Decrypt        |
| CloudWatch     | PutMetricData  |

---

### 禁止

| Service |
| ------- |
| IAM     |
| EC2     |
| EKS     |
| KMS管理操作 |

---

## CloudWatchAgentRole

| Service    | Action          |
| ---------- | --------------- |
| Logs       | CreateLogStream |
| Logs       | PutLogEvents    |
| CloudWatch | PutMetricData   |

---

## EFS CSI Driver

| Service           | Action               |
| ----------------- | -------------------- |
| ElasticFileSystem | DescribeFileSystems  |
| ElasticFileSystem | DescribeMountTargets |

---

## ArgoCD

| Service | Action                |
| ------- | --------------------- |
| ECR     | BatchGetImage         |
| ECR     | GetAuthorizationToken |
| STS     | AssumeRole            |

---

## CodeBuild

| Service         | Action     |
| --------------- | ---------- |
| ECR             | Push/Pull  |
| CloudWatch Logs | Write      |
| S3              | Read/Write |
| SecretsManager  | Read       |

---

# 27. Security Group通信表

---

## SG-ALB

| 送信元      | 送信先 | Port |
| -------- | --- | ---- |
| Internet | ALB | 443  |
| Internet | ALB | 80   |

---

## SG-SystemNode

| 送信元  | 送信先          | Port        |
| ---- | ------------ | ----------- |
| ALB  | Node         | 30000-32767 |
| Node | EKS          | 443         |
| Node | VPC Endpoint | 443         |
| Node | EFS          | 2049        |

---

## SG-WorkloadNode

| 送信元  | 送信先                 | Port        |
| ---- | ------------------- | ----------- |
| ALB  | Node                | 30000-32767 |
| Node | ECR Endpoint        | 443         |
| Node | STS Endpoint        | 443         |
| Node | Secrets Endpoint    | 443         |
| Node | CloudWatch Endpoint | 443         |
| Node | EFS                 | 2049        |

---

## SG-Bastion

| 送信元      | 送信先          | Port |
| -------- | ------------ | ---- |
| Admin IP | Bastion      | 22   |
| Bastion  | EKS API      | 443  |
| Bastion  | VPC Endpoint | 443  |

---

## SG-VpcEndpoint

| 送信元           | 送信先      | Port |
| ------------- | -------- | ---- |
| System Node   | Endpoint | 443  |
| Workload Node | Endpoint | 443  |
| Bastion       | Endpoint | 443  |

---

## SG-EFS

| 送信元           | 送信先 | Port |
| ------------- | --- | ---- |
| System Node   | EFS | 2049 |
| Workload Node | EFS | 2049 |

---

# 28. VPC Endpoint通信表

## ECR API

用途

```text
Docker Image Metadata取得
```

利用者

```text
CodeBuild
Kubelet
Container Runtime
```

---

## ECR DKR

用途

```text
Docker Pull
Docker Push
```

利用者

```text
CodeBuild
Worker Node
```

---

## STS

用途

```text
Pod Identity認証
```

利用者

```text
Application Pod
ArgoCD
CloudWatch Agent
EFS CSI Driver
```

---

## Secrets Manager

用途

```text
アプリケーションシークレット取得
```

利用者

```text
Application Pod
```

---

## KMS

用途

```text
復号
```

利用者

```text
Application Pod
Secrets Manager
EFS
CloudWatch Logs
```

---

## CloudWatch Logs

用途

```text
ログ送信
```

利用者

```text
CloudWatch Agent
```

---

## CloudWatch Monitoring

用途

```text
メトリクス送信
```

利用者

```text
CloudWatch Agent
Application
```

---

## S3

用途

```text
ECR内部通信
CodeBuild Artifact
CloudTrail
```

利用者

```text
CodeBuild
ECR
CloudTrail
```

---

## EKS

用途

```text
Cluster API
```

利用者

```text
Bastion
Node
```

---

## EC2

用途

```text
Karpenter
Node管理
```

利用者

```text
Karpenter
```

---

## AutoScaling

用途

```text
Managed Node Group
```

利用者

```text
EKS
```

---

# 29. CloudFormationディレクトリ構成

## 29.1 Repository構成

```text
infra
├─ templates
│
├─ 01-network
│   ├─ vpc.yaml
│   ├─ subnet.yaml
│   ├─ route.yaml
│   ├─ alb.yaml
│   └─ vpce.yaml
│
├─ 02-security
│   ├─ kms.yaml
│   ├─ iam.yaml
│   └─ cloudtrail.yaml
│
├─ 03-storage
│   ├─ efs.yaml
│   ├─ backup.yaml
│   └─ secrets.yaml
│
├─ 04-eks
│   ├─ cluster.yaml
│   ├─ managed-nodegroup.yaml
│   ├─ addons.yaml
│   └─ pod-identity.yaml
│
├─ 05-monitoring
│   ├─ cloudwatch.yaml
│   ├─ alarms.yaml
│   └─ sns.yaml
│
├─ 06-cicd
│   ├─ ecr.yaml
│   ├─ codebuild.yaml
│   └─ codepipeline.yaml
│
└─ 07-identity
    ├─ cognito.yaml
    ├─ lambda.yaml
    └─ eventbridge.yaml
```

---

## 29.2 Parameter構成

環境差異はParameter化する。

例

```yaml
Parameters:

  Environment:
    Type: String

  VpcCidr:
    Type: String

  ClusterName:
    Type: String
```

---

## 29.3 Export/Import

スタック間連携はExportを利用する。

例

```yaml
Outputs:

  VpcId:
    Export:
      Name: sample-prd-vpc-id
```

---

# 30. Pod Identity Association一覧

## 30.1 管理方針

Pod Identity AssociationはCloudFormation管理とする。

NamespaceおよびServiceAccount作成後に関連付ける。

---

## 30.2 Association一覧

| Namespace   | ServiceAccount        | IAM Role            |
| ----------- | --------------------- | ------------------- |
| argocd      | argocd-server         | ArgoCdRole          |
| monitoring  | cloudwatch-agent      | CloudWatchAgentRole |
| kube-system | efs-csi-controller-sa | EfsCsiRole          |
| app-prod    | app-sa                | ApplicationRole     |
| app-stg     | app-sa                | ApplicationRole     |

---

## 30.3 CloudFormation定義

```yaml
AppPodIdentityAssociation:

  Type: AWS::EKS::PodIdentityAssociation

  Properties:

    ClusterName: !Ref ClusterName

    Namespace: app-prod

    ServiceAccount: app-sa

    RoleArn: !GetAtt ApplicationRole.Arn
```

---

# 31. Karpenter設計

## 31.1 EC2NodeClass

名称

```text
default-workload
```

---

YAML仕様

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

---

## 31.2 NodePool（一般業務）

名称

```text
general
```

---

YAML仕様

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
        values:
        - amd64

      - key: karpenter.sh/capacity-type
        operator: In
        values:
        - spot
        - on-demand

      - key: node.kubernetes.io/instance-type
        operator: In
        values:
        - c6i.large
        - c6i.xlarge
        - m6i.large
        - m6i.xlarge

  disruption:

    consolidationPolicy: WhenEmptyOrUnderutilized

    expireAfter: 720h
```

---

## 31.3 NodePool（Batch）

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

---

## 31.4 System Pod配置制御

System PodはManaged Node Groupへ固定配置する。

Deploymentへ以下を設定する。

```yaml
nodeSelector:

  node-role: system
```

---

# 32. ArgoCD Application仕様

## 32.1 Repository構成

```text
gitops
│
├─ applications
│
├─ base
│   ├─ api
│   ├─ admin
│   └─ batch
│
└─ overlays
    ├─ dev
    ├─ stg
    └─ prod
```

---

## 32.2 Application定義

### APIサービス

```yaml
apiVersion: argoproj.io/v1alpha1

kind: Application

metadata:

  name: app-api

  namespace: argocd

spec:

  project: default

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

---

## 32.3 Application命名規則

```text
app-api
app-admin
app-batch
```

---

## 32.4 ArgoCD Project

用途別にProjectを分離する。

```text
application
platform
monitoring
```

---

# 33. Kubernetes Manifest標準

## Namespace

```yaml
metadata:

  labels:

    environment: prod

    owner: application
```

---

## Deployment

必須項目

```yaml
resources:

  requests:

    cpu: 250m

    memory: 512Mi

  limits:

    cpu: 1000m

    memory: 1024Mi
```

---

## PodDisruptionBudget

全サービス必須

```yaml
minAvailable: 1
```

---

## HPA

全APIサービス必須

```yaml
minReplicas: 2

maxReplicas: 10

targetCPUUtilizationPercentage: 70
```

---

# 34. Secrets Store CSI Driver仕様

## SecretProviderClass

例

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

---

## Pod

```yaml
volumes:

- name: secrets-store

  csi:

    driver: secrets-store.csi.k8s.io

    readOnly: true

    volumeAttributes:

      secretProviderClass: app-secret
```

---

# 35. Karpenter運用ルール

## Spot優先

全NodePoolでSpotを優先する。

---

## OnDemandフォールバック

Spot不足時のみOnDemand利用。

---

## AZ分散

最低2AZへ分散。

---

## ノード寿命

```yaml
expireAfter: 720h
```

30日毎に再作成。

---

# 36. 実装完了判定基準

以下を満たした場合に実装完了とする。

### 基盤

* VPC作成完了
* Endpoint作成完了
* EKS作成完了
* Pod Identity有効

### CI/CD

* CodeBuild成功
* ECR Push成功
* ArgoCD同期成功

### アプリ

* Pod起動成功
* Secrets取得成功
* EFSマウント成功

### 監視

* Container Insights有効
* ログ出力確認
* アラーム通知確認

### セキュリティ

* 全ストレージ暗号化
* Secrets Manager利用
* KMS利用
* Endpoint経由通信確認

---

