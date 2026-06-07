# EKSアプリケーション実行基盤 仕様書

**ドキュメントID:** INFRA-EKS-001  
**バージョン:** 2.0  
**ステータス:** Draft  
**最終更新:** 2025年  
**次回レビュー予定:** 構築完了後30日以内

---

# 目次

0. [ドキュメント管理](#0-ドキュメント管理)
1. [システム構成](#1-システム構成)
2. [ネットワーク設計](#2-ネットワーク設計)
3. [EKSクラスタ設計](#3-EKSクラスタ設計)
4. [認証・Pod Identity設計](#4-認証・Pod Identity設計)
5. [認証・認可設計（ユーザ向け）](#5-認証・認可設計（ユーザ向け）)
6. [セキュリティ設計](#6-セキュリティ設計)
7. [CI/CD設計](#7-CI/CD設計)
8. [ストレージ設計](#8-ストレージ設計)
9. [監視・ロギング設計](#9-監視・ロギング設計)
10. [コスト管理](#10-コスト管理)
11. [非機能要件トレーサビリティマトリクス](#11-非機能要件トレーサビリティマトリクス)
12. [Kubernetes設計詳細](#12-Kubernetes設計詳細)
13. [CloudFormation構成](#13-CloudFormation構成)
14. [命名規約・タグ付け](#14-命名規約・タグ付け)
15. [運用手順・Runbook](#15-運用手順・Runbook)
16. [実装完了判定基準](#16-実装完了判定基準)

---

# 0. ドキュメント管理

## 0.1 対象読者と役割

| 役割 | 主な参照箇所 | 権限 |
|---|---|---|
| Platform SRE | 全セクション | 設計決定・変更承認 |
| アプリケーション開発者 | 4・5・10章 | 参照・実装 |
| セキュリティ担当 | 2・5・8章 | レビュー・承認 |
| 運用（Ops） | 7・8・9章 | 参照・実行 |
| コスト管理 | 10章 | 参照 |

## 0.2 設計変更プロセス

本仕様書の内容を変更する場合、以下のプロセスを経ること。

```
変更提案（GitHub Issue / RFC）
    ↓
設計レビュー（Platform SRE + 関係者）
    ↓
セキュリティ確認（セキュリティ担当）
    ↓
承認（Platform SRE リード）
    ↓
仕様書更新（PR・レビュー・Merge）
    ↓
実装・反映
```

**緊急変更（障害対応時）：** Platform SREリードの口頭承認後に実施し、事後72時間以内に仕様書を更新する。

## 0.3 設計と実装の境界

| 本仕様書が定めるもの | 実装者が判断するもの |
|---|---|
| 採用するAWSサービスと構成 | CloudFormationパラメータの具体値（CIDRブロック等） |
| セキュリティ方針・禁止事項 | モジュール内のリソース細部 |
| 命名規約・タグ規約 | ローカル変数名・コメント |
| 非機能要件と受入基準 | ライブラリ・ツールのマイナーバージョン |

## 0.4 用語定義

| 用語 | 定義 |
|---|---|
| System Node | Managed Node Group上のシステムコンポーネント専用ノード |
| Workload Node | Karpenterが動的にプロビジョニングするアプリ専用ノード |
| GitOpsリポジトリ | Kubernetes Manifestを管理するリポジトリ（アプリコードとは分離） |
| Pod Identity | EKS Pod Identity（IRSAの後継、OIDC不要） |
| prd / stg / dev | 本番 / 検証 / 開発 環境の識別子 |

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
ALB（TLS終端・WAF・HTTP→HTTPS強制リダイレクト）
    │
    ▼
EKS Cluster
 ├─ System Node Group（Managed・固定2台）
 │   ├─ ArgoCD
 │   ├─ Metrics Server
 │   ├─ EFS CSI Driver
 │   ├─ CloudWatch Agent
 │   └─ Karpenter
 │
 └─ Karpenter Node（Spot優先・動的プロビジョニング）
     └─ Application Pods

ECR ◄── CodeBuild（CI：Build → Test → Scan → Sign → Push）

Secrets Manager / KMS / EFS / CloudWatch

Bastion EC2（SSM Session Manager経由 または Admin IP限定SSH）
```

## 1.2 主要コンポーネント

| コンポーネント | 役割 | 備考 |
|---|---|---|
| EKS | コンテナオーケストレーション | Managed Control Plane |
| Karpenter | ワークロードノードの自動スケール | Spot優先、OnDemandフォールバック |
| ArgoCD | GitOpsベースのCD | Auto Sync / Self Heal |
| CodeBuild | コンテナイメージのCI | Git Push → Build → Scan → Sign → Push |
| ALB | 外部通信の入口 | WAF必須、HTTP→HTTPS強制 |
| EFS | 共有ストレージ | CSI Driverで連携、Access Pointで用途分離 |
| Secrets Manager | シークレット管理 | KMS CMKで暗号化、90日ローテーション |
| CloudWatch | 監視・ロギング | Container Insights有効、365日保持 |
| Cognito | ユーザ認証 | JWT発行のみ、セッション管理はApp側 |

---

# 2. ネットワーク設計

## 2.1 基本方針

| 方針 | 詳細 |
|---|---|
| VPC Endpoint優先 | AWSサービスとの通信はすべてPrivateLink経由 |
| NAT最小化 | ワークロードノードはNATを使用しない（VPC Endpoint経由） |
| Egress制限 | Podからの外部インターネット通信は原則禁止 |
| 例外的Egress | 以下のみ許可（[2.6節](#26-egress制御詳細)参照） |

**インターネットアクセスを許可する通信（例外一覧）：**

| 送信元 | 宛先 | 用途 | 経路 |
|---|---|---|---|
| ALB | Internet | 外部公開 | Internet Gateway |
| Bastion | Internet | 運用作業（パッケージ取得等） | NAT Gateway |
| Cognito | Internet | 認証基盤（AWS管理） | AWS管理ネットワーク |
| System Node | apt/dnf | OSパッケージ取得（初期化時のみ） | NAT Gateway（必要時） |

## 2.2 VPC構成

### VPC

| 項目 | 値 |
|---|---|
| CIDR | 10.0.0.0/16 |
| DNS解決 | 有効（enableDnsSupport: true） |
| DNSホスト名 | 有効（enableDnsHostnames: true） |

### サブネット（各AZ×2構成）

| 名称 | CIDR例 | 配置対象 | ルーティング先 |
|---|---|---|---|
| Public-AZ1/2 | 10.0.0.0/24, 10.0.1.0/24 | ALB、Bastion | Internet Gateway |
| Private-System-AZ1/2 | 10.0.10.0/24, 10.0.11.0/24 | Managed Node Group | NAT Gateway（限定） |
| Private-App-AZ1/2 | 10.0.20.0/24, 10.0.21.0/24 | Karpenter Node | VPC Endpoint のみ |
| Private-Endpoint-AZ1/2 | 10.0.30.0/24, 10.0.31.0/24 | VPC Endpoint ENI | - |

### Route Table設計

| Route Table | 対象サブネット | デフォルトルート先 | 備考 |
|---|---|---|---|
| PublicRouteTable | Public | Internet Gateway | ALB・Bastion用 |
| PrivateSystemRouteTable | Private-System | NAT Gateway | 限定的な外部通信用 |
| PrivateAppRouteTable | Private-App | なし（ローカルのみ） | VPC Endpoint経由のみ |

> **重要:** Private-Appサブネットにはデフォルトルート（0.0.0.0/0）を設定しない。VPC Endpoint経由の通信のみ許可することでワークロードPodのEgressを物理的に制限する。

## 2.3 VPC Endpoint

AWSサービスへの通信はすべて以下のEndpoint経由とする。各InterfaceエンドポイントはPrivate-Endpointサブネットに配置する。

| サービス | 種別 | Endpoint Policy |
|---|---|---|
| ECR API | Interface | ECRリポジトリをAWSアカウント内に限定 |
| ECR DKR | Interface | 同上 |
| S3 | Gateway | 対象バケットをアカウント内に限定 |
| CloudWatch Logs | Interface | PutLogEvents・CreateLogStream のみ |
| CloudWatch Monitoring | Interface | PutMetricData のみ |
| STS | Interface | AssumeRoleWithWebIdentity のみ |
| EKS | Interface | 自クラスタのみ |
| EC2 | Interface | アカウント内リソースのみ |
| Autoscaling | Interface | アカウント内リソースのみ |
| Secrets Manager | Interface | 自アカウントのシークレットのみ |
| KMS | Interface | 自アカウントのキーのみ |
| SSM | Interface | Session Manager用 |
| SSM Messages | Interface | Session Manager用 |
| EC2 Messages | Interface | Session Manager用 |

### VPC Endpointポリシー例（Secrets Manager）

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": "*",
      "Action": [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret"
      ],
      "Resource": "arn:aws:secretsmanager:ap-northeast-1:<ACCOUNT_ID>:secret:*",
      "Condition": {
        "StringEquals": {
          "aws:PrincipalAccount": "<ACCOUNT_ID>"
        }
      }
    }
  ]
}
```

## 2.4 Network ACL

各サブネット層でNACLによる多層防御を実施する。

| NACL | インバウンド許可 | アウトバウンド許可 |
|---|---|---|
| Public | 443, 80（Internet）、SSH（Admin IP） | All |
| Private-System | VPC内部通信 | VPC内部、NAT経由（限定） |
| Private-App | VPC内部通信（ALB→30000-32767等） | VPC内部のみ |
| Private-Endpoint | VPC内部443 | VPC内部443 |

## 2.5 Security Group通信設計

### SG-ALB

| 送信元 | 送信先 | Port | 用途 |
|---|---|---|---|
| Internet（0.0.0.0/0） | ALB | 443 | HTTPS受信 |
| Internet（0.0.0.0/0） | ALB | 80 | HTTP受信（→443リダイレクト） |

### SG-SystemNode

| 送信元 | 送信先 | Port | 用途 |
|---|---|---|---|
| ALB SG | Node | 30000-32767 | NodePort |
| Node self | Node self | ALL | ノード間通信 |
| Node | EKS（SG） | 443 | API Server通信 |
| Node | VPC Endpoint SG | 443 | AWSサービス |
| Node | EFS SG | 2049 | ファイルマウント |

### SG-WorkloadNode

| 送信元 | 送信先 | Port | 用途 |
|---|---|---|---|
| ALB SG | Node | 30000-32767 | NodePort |
| Node self | Node self | ALL | ノード間通信 |
| Node | VPC Endpoint SG | 443 | AWSサービス（ECR/STS/Secrets/CW） |
| Node | EFS SG | 2049 | ファイルマウント |

### SG-Bastion

| 送信元 | 送信先 | Port | 用途 |
|---|---|---|---|
| Admin IP（/32） | Bastion | 22 | SSH（緊急時のみ。通常はSSM） |
| Bastion | EKS API（SG） | 443 | kubectl |
| Bastion | VPC Endpoint SG | 443 | AWSサービス |

### SG-VpcEndpoint

| 送信元 | Port |
|---|---|
| System Node SG | 443 |
| Workload Node SG | 443 |
| Bastion SG | 443 |

### SG-EFS

| 送信元 | Port |
|---|---|
| System Node SG | 2049 |
| Workload Node SG | 2049 |

## 2.6 Egress制御詳細

### ワークロードノードのEgress制限フロー

```
Application Pod（Egress）
    │
    ▼
[Private-App サブネット]
    │
    ├─ VPC Endpointへのルーティング → 許可（ECR/Secrets等）
    │
    └─ デフォルトルートなし → インターネットへのEgress 物理的に不可
```

### Kubernetes NetworkPolicyによるPodレベル制御

ワークロードNamespaceに以下のNetworkPolicyをデフォルト適用する（ルーティング制限に加えた多重防御）。

```yaml
# デフォルト拒否（Namespace内で必ず適用）
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-egress
  namespace: app-prod
spec:
  podSelector: {}
  policyTypes:
    - Egress
  egress:
    # VPC内部通信のみ許可（AWSサービスはVPC Endpoint経由）
    - ports:
        - port: 443
          protocol: TCP
        - port: 2049
          protocol: TCP
    - to:
        - ipBlock:
            cidr: 10.0.0.0/16
```

### OSパッケージ取得（例外的Egress）

ノードの初期化時（UserData実行時）にのみ、System NodeサブネットからNAT Gateway経由でのパッケージ取得を許可する。運用中の定期アップデートは事前検証済みのAMIを再デプロイする方式とする。

---

# 3. EKSクラスタ設計

## 3.1 Kubernetesバージョン

| 項目 | 方針 |
|---|---|
| バージョン選定 | AWSがサポートする最新の安定版（例：1.33） |
| アップグレード頻度 | 年2回を目安に計画実施 |
| サポート終了対応 | EOL 60日前までに次バージョンへ更新 |

## 3.2 ノード構成

### システムノード（Managed Node Group）

| 項目 | 値 |
|---|---|
| 種別 | Managed Node Group |
| 台数（通常時） | 2台 |
| 最小 / 最大 | 2 / 4 |
| ラベル | `node-role=system` |
| Taint | `node-role=system:NoSchedule` |

配置Pod（`nodeSelector: node-role=system` を必ず設定すること）：

- CoreDNS
- ArgoCD
- Karpenter
- Metrics Server
- CloudWatch Agent
- EFS CSI Driver

**アプリケーションPodのSystem Nodeへの配置は禁止する。**

### ワークロードノード（Karpenter管理）

| 項目 | 値 |
|---|---|
| 種別 | Karpenter動的プロビジョニング |
| ラベル | `node-role=workload` |
| キャパシティ | Spot優先、不足時OnDemand |
| AZ分散 | 最低2AZ |
| ノード寿命 | 720h（30日ごとに再作成） |

## 3.3 Namespace設計

| Namespace | 用途 | ラベル |
|---|---|---|
| argocd | ArgoCDコンポーネント | owner: platform, environment: shared |
| kube-system | AWS Addon（VPC CNI等） | - |
| monitoring | CloudWatch Agent | owner: platform, environment: shared |
| karpenter | Karpenter | owner: platform, environment: shared |
| app-prod | 本番アプリケーション | owner: application, environment: prod |
| app-stg | 検証アプリケーション | owner: application, environment: stg |

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
    ManagedBy: karpenter
```

### NodePool — general（通常業務）

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
    expireAfter: 720h
```

### NodePool — batch（バッチ専用）

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

| ルール | 設定 | 理由 |
|---|---|---|
| Spot優先 | capacity-type: spot > on-demand | コスト削減 |
| OnDemandフォールバック | Spot不足時のみ | 可用性担保 |
| AZ分散 | 最低2AZ | 障害局所化 |
| ノード寿命 | expireAfter: 720h | セキュリティパッチ適用・ドリフト防止 |
| Consolidation | WhenEmptyOrUnderutilized | コスト最適化 |

---

# 4. 認証・Pod Identity設計

## 4.1 基本方針

AWSリソースへのアクセスは**Pod Identityのみ**使用する。

| 手段 | 採否 | 理由 |
|---|---|---|
| Pod Identity | **採用** | OIDC不要、設定シンプル、AWSネイティブ |
| IRSA（IAM Roles for Service Accounts） | **禁止** | 新規構築のためPod Identityに統一。OIDC管理コストの削減 |
| IAM User / AccessKey | **禁止** | 静的クレデンシャルのリスク（漏洩・ローテーション負荷） |
| Kubernetes Secret（AWS認証情報） | **禁止** | etcdに平文保存されるリスク |

## 4.2 Pod Identityアーキテクチャ

```
[Application Pod]
      │
      │ AWS API呼び出し（例：GetSecretValue）
      ▼
[EKS Pod Identity Agent（DaemonSet）]
      │
      │ ServiceAccount + Namespace をキーに
      │ Pod Identity Association を参照
      ▼
[EKS Pod Identity Service]
      │
      │ 一時クレデンシャル発行
      ▼
[IAM Role（ApplicationRole）]
      │
      ▼
[AWSサービス（Secrets Manager等）]
```

## 4.3 Pod Identity Association一覧

| Namespace | ServiceAccount | IAM Role | 目的 |
|---|---|---|---|
| argocd | argocd-server | ArgoCDRole | ECRアクセス、STS |
| monitoring | cloudwatch-agent | CloudWatchAgentRole | ログ・メトリクス送信 |
| kube-system | efs-csi-controller-sa | EFSRole | EFSマウント管理 |
| app-prod | app-sa | ApplicationRole | Secrets・KMS・CW |
| app-stg | app-sa | ApplicationRole | Secrets・KMS・CW |

## 4.4 CloudFormation作成順序

Pod Identityは以下の順で作成する。順序を誤るとAssociation作成に失敗する。

```
1. EKS Cluster（04-eks/cluster.yaml）
      ↓
2. IAM Role（02-security/iam.yaml）
      ↓
3. Pod Identity Addon有効化（04-eks/addons.yaml）
      ↓
4. Namespace・ServiceAccount作成（kubectl apply）
      ↓
5. Pod Identity Association（04-eks/pod-identity.yaml）
```

### CloudFormation定義例

```yaml
AppPodIdentityAssociation:
  Type: AWS::EKS::PodIdentityAssociation
  DependsOn:
    - PodIdentityAddon
  Properties:
    ClusterName: !Ref ClusterName
    Namespace: app-prod
    ServiceAccount: app-sa
    RoleArn: !GetAtt ApplicationRole.Arn
```

## 4.5 IAM最小権限ポリシー雛形

### ApplicationRole

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "SecretsManagerAccess",
      "Effect": "Allow",
      "Action": ["secretsmanager:GetSecretValue"],
      "Resource": "arn:aws:secretsmanager:ap-northeast-1:<ACCOUNT_ID>:secret:/prod/sample/*"
    },
    {
      "Sid": "KMSDecrypt",
      "Effect": "Allow",
      "Action": ["kms:Decrypt", "kms:GenerateDataKey"],
      "Resource": "arn:aws:kms:ap-northeast-1:<ACCOUNT_ID>:key/<SECRETS_KMS_KEY_ID>"
    },
    {
      "Sid": "CloudWatchMetrics",
      "Effect": "Allow",
      "Action": ["cloudwatch:PutMetricData"],
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "cloudwatch:namespace": "Application/sample"
        }
      }
    }
  ]
}
```

### Trust Policy（Pod Identity用）

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "pods.eks.amazonaws.com"
      },
      "Action": ["sts:AssumeRole", "sts:TagSession"]
    }
  ]
}
```

## 4.6 Pod Identity検証手順

### Association確認

```bash
# Association一覧確認
aws eks list-pod-identity-associations \
  --cluster-name sample-prd-eks \
  --region ap-northeast-1

# 特定Associationの詳細確認
aws eks describe-pod-identity-association \
  --cluster-name sample-prd-eks \
  --association-id <ASSOCIATION_ID> \
  --region ap-northeast-1
```

### Pod内からの動作確認

```bash
# Podに入って確認
kubectl exec -n app-prod -it <POD_NAME> -- /bin/sh

# 一時クレデンシャルが取得できることを確認
aws sts get-caller-identity

# Secrets Managerへのアクセス確認
aws secretsmanager get-secret-value \
  --secret-id /prod/sample/app/db-password \
  --region ap-northeast-1
```

**期待結果:** `get-caller-identity` のARNが `ApplicationRole` であること。

---

# 5. 認証・認可設計（ユーザ向け）

## 5.1 クラスタ管理者アクセス（Windows端末）

AWS IAM Identity Centerで認証後、以下のコマンドでkubeconfigを取得する。

```powershell
aws eks update-kubeconfig `
  --region ap-northeast-1 `
  --name eks-prod
```

## 5.2 Bastion EC2

| 項目 | 内容 |
|---|---|
| 通常アクセス | SSM Session Manager（SSHキー不要） |
| 緊急SSH | Admin IPのみ許可（ポート22） |
| 配置 | Public Subnet |
| 用途 | kubectl、helm、aws cli |

## 5.3 アプリケーションログイン（Cognito）

### 認証フロー

```
User
  ↓（ID/PW）
Cognito（認証・JWT発行）
  ↓（JWT Token）
Application（JWT検証 → Sessionを独自発行）
```

| 役割 | 担当 |
|---|---|
| 認証（ID/PW検証） | Cognito |
| JWT発行 | Cognito |
| セッション管理 | Application（Cognitoのセッション機能は使用しない） |

## 5.4 ユーザ状態変更の検知

```
Cognito（ユーザ追加/削除/無効化）
  ↓
CloudTrail（API呼び出し記録）
  ↓
EventBridge（イベントルーティング）
  ↓
Lambda（通知処理）
  ↓
Application API（独自ユーザ状態反映）
```

通知対象イベント：ユーザ追加、ユーザ削除、ユーザ無効化

---

# 6. セキュリティ設計

## 6.1 通信暗号化

全通信でTLS 1.2以上を使用する。TLS 1.0 / 1.1は禁止する。

## 6.2 Kubernetes Secretの禁止

アプリの機密情報を `kind: Secret` に格納することを禁止する。シークレットはすべてSecrets Manager + Secrets Store CSI Driverで提供する。

```yaml
# ❌ 禁止
kind: Secret
```

AdmissionコントローラでSecretリソースの作成をブロックする（[6.5節](#65-admissionコントローラ)参照）。

## 6.3 コンテナイメージ管理

- イメージ取得元はECRのみ許可する
- DockerHubなど外部レジストリからの直接Pullは禁止する
- イメージタグ `latest` によるデプロイは禁止する（Immutable tag必須）

## 6.4 イメージセキュリティ（サプライチェーン）

### スキャンポリシー

| 脆弱性レベル | 対応 |
|---|---|
| CRITICAL | デプロイ禁止（CIでブロック） |
| HIGH | デプロイ禁止（CIでブロック） |
| MEDIUM | 警告・記録（翌スプリントで対応） |
| LOW / INFO | 記録のみ |

### SBOM・署名

| 対応 | ツール | タイミング |
|---|---|---|
| SBOM生成 | syft | CIパイプライン（ECR Push前） |
| イメージ署名 | cosign（キーレス） | ECR Push後 |
| 署名検証 | cosign verify | デプロイ前（Admission Webhook） |

### CIパイプライン詳細フロー

```
Git Push
  ↓
CodeBuild起動
  ↓
Docker Build
  ↓
Unit Test
  ↓
ECR Enhanced Scanning（CRITICAL/HIGHで強制停止）
  ↓
SBOM生成（syft → ECRに付与）
  ↓
ECR Push（Immutableタグ：git-sha）
  ↓
cosign署名（キーレス、Sigstore Rekor記録）
  ↓
GitOpsリポジトリ更新（イメージタグのみ更新）
```

### イメージタグ

| タグ | 用途 | Mutable |
|---|---|---|
| `<git-sha>` | 主タグ（デプロイに使用） | No（Immutable） |
| `<version>` | セマンティックバージョン | No |
| `latest` | **使用禁止** | - |

### ECR Lifecycleポリシー

コストとリポジトリ肥大化を防ぐため、以下のLifecycleポリシーを適用する。

```json
{
  "rules": [
    {
      "rulePriority": 1,
      "description": "untaggedイメージを7日で削除",
      "selection": {
        "tagStatus": "untagged",
        "countType": "sinceImagePushed",
        "countUnit": "days",
        "countNumber": 7
      },
      "action": { "type": "expire" }
    },
    {
      "rulePriority": 2,
      "description": "50世代を超えたイメージを削除",
      "selection": {
        "tagStatus": "tagged",
        "tagPrefixList": ["sha-"],
        "countType": "imageCountMoreThan",
        "countNumber": 50
      },
      "action": { "type": "expire" }
    }
  ]
}
```

## 6.5 Admissionコントローラ

### PodSecurity Admission（PSA）

各Namespaceに適切なPodSecurity標準を適用する。

| Namespace | レベル | 制約内容 |
|---|---|---|
| app-prod / app-stg | restricted | 特権コンテナ禁止、rootfs ReadOnly、seccompProfile必須 |
| kube-system | privileged | AWS Addon動作に必要 |
| argocd | baseline | 非特権・HostNetwork禁止 |
| monitoring | baseline | CloudWatch Agent（一部特権機能が必要） |
| karpenter | baseline | ノード管理に必要な権限 |

Namespaceラベル設定例（app-prod）：

```yaml
metadata:
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
```

### OPA Gatekeeper（推奨）

以下のConstraintTemplateを必須として導入する。

| ルール名 | 内容 |
|---|---|
| NoLatestTag | `latest`タグのイメージデプロイを禁止 |
| RequiredLabels | 必須ラベル（owner/environment）の付与を強制 |
| AllowedRegistries | ECR以外のレジストリからのPullを禁止 |
| NoSecretKind | `kind: Secret` のManifest適用を禁止 |
| RequiredResourceLimits | CPU/Memoryリソース制限の設定を強制 |

```yaml
# AllowedRegistries例
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sAllowedRepos
metadata:
  name: allowed-repos
spec:
  match:
    kinds:
      - apiGroups: [""]
        kinds: ["Pod"]
  parameters:
    repos:
      - "<ACCOUNT_ID>.dkr.ecr.ap-northeast-1.amazonaws.com"
```

## 6.6 暗号化

KMS CMKを全ストレージリソースに適用する。

| 対象リソース | KMSキー | ローテーション |
|---|---|---|
| EBS（Nodeルートボリューム） | EksKmsKey | 年1回（自動） |
| EFS | EfsKmsKey | 年1回（自動） |
| Secrets Manager | SecretsKmsKey | 年1回（自動） |
| CloudWatch Logs | LogsKmsKey | 年1回（自動） |
| ECR | EksKmsKey | 年1回（自動） |
| etcd（EKS Control Plane） | EKS管理キー | AWS管理 |

### KMSキー管理方針

- CMKは目的別に分離する（共用禁止）
- キー削除には30日の待機期間を設ける
- キー管理操作（Create/Delete/Disable）はPlatform SREのみ可能とする
- 年次でキー棚卸しを実施する

---

# 7. CI/CD設計

## 7.1 CI（CodeBuild）

### CIフロー

```
Git Push
  ↓
CodeBuild起動
  ↓
Docker Build
  ↓
Unit Test
  ↓
ECR Enhanced Scanning（CRITICAL/HIGHで強制停止）
  ↓
SBOM生成（syft）
  ↓
ECR Push（Immutableタグ）
  ↓
cosign署名
  ↓
GitOpsリポジトリのイメージタグ更新
```

## 7.2 CD（ArgoCD）

### GitOpsリポジトリ構成

```
gitops/
├─ applications/       # ArgoCD Application定義
├─ base/               # Kustomize base
│   ├─ api/
│   ├─ admin/
│   └─ batch/
└─ overlays/
    ├─ dev/
    ├─ stg/
    └─ prod/
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
| Auto Sync | Enabled | GitOpsリポジトリ変更を自動適用 |
| Self Heal | Enabled | クラスタとGitの差分を自動修復 |
| Prune | Enabled | Git削除リソースを自動削除 |

### ArgoCD Project分離

| Project | 用途 |
|---|---|
| application | アプリケーション系 |
| platform | インフラ・基盤系 |
| monitoring | 監視系 |

### Application定義例（APIサービス）

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

---

# 8. ストレージ設計

## 8.1 EFS（共有ストレージ）

| 項目 | 値 |
|---|---|
| 名称 | sample-prd-efs |
| Performance Mode | General Purpose |
| Throughput Mode | Elastic |
| 暗号化 | KMS CMK（EfsKmsKey） |

### Access Point（用途別分離）

| Access Point | 用途 |
|---|---|
| app-upload | ファイルアップロード |
| app-share | アプリ間ファイル共有 |
| batch-work | バッチ作業領域 |

### Kubernetes連携

```yaml
# StorageClass
provisioner: efs.csi.aws.com
parameters:
  provisioningMode: efs-ap
```

## 8.2 Secrets Manager

### 保存対象と命名規則

```
/<env>/<system>/<service>/<name>

例：/prod/sample/app/db-password
    /prod/sample/app/jwt-secret
    /prod/sample/app/api-key
```

### ローテーション設定

| 対象 | 周期 | ローテーション方式 |
|---|---|---|
| DBパスワード | 90日 | Lambda自動ローテーション |
| APIキー | 90日 | 手動（ローテーション手順書参照） |
| JWT署名鍵 | 180日 | 手動 |

### Secrets Store CSI Driver連携

```yaml
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: app-secret
  namespace: app-prod
spec:
  provider: aws
  parameters:
    objects: |
      - objectName: "/prod/sample/app/db-password"
        objectType: "secretsmanager"
      - objectName: "/prod/sample/app/jwt-secret"
        objectType: "secretsmanager"
```

## 8.3 バックアップ・リストア

### EFSバックアップ

| 項目 | 値 |
|---|---|
| バックアップツール | AWS Backup |
| 頻度 | 日次 |
| 保持期間 | 35日（日次）、12ヶ月（月次） |
| バックアップ先 | 同一リージョン（別Vaultで分離） |
| RTO目標 | 4時間以内 |
| RPO目標 | 1時間以内 |

### Secrets Managerのバックアップ

Secrets Managerはバージョン管理が組み込まれているため、削除保護（DeletionProtection）を有効化したうえで運用する。緊急の手動バックアップ手順：

```bash
# シークレット一覧を取得してS3にバックアップ（本番では自動化する）
aws secretsmanager list-secrets --region ap-northeast-1 \
  | jq -r '.SecretList[].Name' \
  | xargs -I{} aws secretsmanager get-secret-value --secret-id {} \
  | jq '{Name: .Name, SecretString: .SecretString}' \
  > /tmp/secrets-backup-$(date +%Y%m%d).json
# ※出力ファイルは暗号化して管理すること
```

### リストア検証（四半期実施）

```
1. バックアップVaultから検証用EFSにリストア
2. 検証用PodをマウントしてファイルI/Oを確認
3. リストア所要時間を記録（RTO検証）
4. 結果をインシデント管理システムに記録
```

---

# 9. 監視・ロギング設計

## 9.1 監視基盤

CloudWatchをメイン監視基盤として使用し、Container Insightsを有効化する。

## 9.2 ログ収集

| ログ種別 | LogGroup | 保持期間 | 暗号化 |
|---|---|---|---|
| Application Log | /eks/prod/application | 365日 | KMS |
| Kubernetes System Log | /eks/prod/system | 365日 | KMS |
| Audit Log | /eks/prod/audit | 365日 | KMS |

## 9.3 アラート設計（重要度分類）

アラートは重要度（P0〜P3）で分類し、対応優先度とエスカレーションを決定する。

| 重要度 | 定義 | 初動目標 | 通知先 | エスカレーション |
|---|---|---|---|---|
| P0 | サービス停止・データ損失リスク | 15分以内 | PagerDuty（オンコール） | 30分でリードSRE |
| P1 | 機能劣化・パフォーマンス低下 | 30分以内 | PagerDuty | 1時間でリードSRE |
| P2 | 警告・閾値接近 | 翌営業日中 | Slack (#infra-alert) | 対応なしで翌日エスカレ |
| P3 | 情報・傾向把握 | 週次レビュー | Slack (#infra-info) | なし |

### アラート一覧

| 監視対象 | 条件 | 重要度 | 関連Runbook |
|---|---|---|---|
| NodeNotReady | 1件以上発生 | P0 | RB-001 |
| EKS Control Plane接続不可 | APIサーバ応答なし | P0 | RB-002 |
| CrashLoopBackOff | 1件以上発生 | P1 | RB-003 |
| ArgoCD同期失敗 | Sync Status = Failed | P1 | RB-004 |
| CPU使用率 | Node > 80%（5分継続） | P2 | RB-005 |
| Memory使用率 | Node > 80%（5分継続） | P2 | RB-005 |
| Disk使用率 | Node > 80% | P2 | RB-005 |
| EFS容量 | > 閾値（TBD） | P2 | RB-006 |
| ECR脆弱性 | CRITICAL検出 | P1 | RB-007 |
| コスト予算超過 | 月予算の80%超 | P2 | - |

### アラート抑止（メンテナンス窓口）

定期メンテナンス中のアラートノイズを防ぐため、CloudWatch Alarm suppressor または SNS filter を使用する。

```bash
# メンテナンス開始時（アラームをOK扱いに）
aws cloudwatch set-alarm-state \
  --alarm-name "NodeNotReady" \
  --state-value OK \
  --state-reason "Maintenance window"

# 自動化: EventBridgeスケジュールでメンテ窓口を管理する
```

## 9.4 ダッシュボード

CloudWatch Dashboardとして以下を作成する（CloudFormationで管理）。

| ダッシュボード名 | 内容 |
|---|---|
| cluster-overview | ノード数・CPU/Mem・Pod数・エラー率 |
| application | Podごとのリクエスト数・レイテンシ・エラー |
| cicd | CIビルド成功率・デプロイ頻度・Sync状態 |
| cost | 日次コスト・Spot割合・リソース使用効率 |

## 9.5 ALB設計

| 項目 | 値 |
|---|---|
| Ingress Controller | AWS Load Balancer Controller |
| Scheme | internet-facing |
| TLS証明書 | ACM |
| HTTP（80番） | 443へリダイレクト |
| WAF | 必須（AWS Managed Rules） |

---

# 10. コスト管理

## 10.1 コストモデル（参考）

| コンポーネント | 想定レンジ | 変動要因 |
|---|---|---|
| EKS Control Plane | 固定（~$73/月） | - |
| System Node Group（2台・固定） | 中 | インスタンスタイプ |
| Karpenter Node（Spot） | 変動・低 | ワークロード量 |
| EFS | 変動 | 保存データ量 |
| ALB | 低〜中 | リクエスト数 |
| CloudWatch | 低〜中 | ログ量・メトリクス数 |
| NAT Gateway | 低 | 外部通信量（最小化） |
| ECR | 低 | イメージ数・サイズ |

Spot利用によりワークロードノードのコストを**オンデマンド比 最大70%削減**を目標とする。

## 10.2 コストアラート

| 閾値 | アクション |
|---|---|
| 月予算の80% | Slack通知（P2アラート） |
| 月予算の100% | PagerDuty通知（P1アラート）+ 管理者へのメール |

AWS Budgets + SNSで設定し、CloudFormation（05-monitoring）で管理する。

## 10.3 コスト最適化ルール

- Karpenterのconsolidationを常時有効（`WhenEmptyOrUnderutilized`）
- ECR Lifecycleポリシーで不要イメージを自動削除（[6.4節](#64-イメージセキュリティサプライチェーン)参照）
- CloudWatch Logsのリテンションを365日に厳守（無期限保持禁止）
- 月次でKubernetes resource requestsの適正化レビューを実施

---

# 11. 非機能要件トレーサビリティマトリクス

各非機能要件に対して、対応する設計項目・検証方法・受入基準を紐付ける。

| # | 要件 | 設計項目 | 検証方法 | 受入基準 |
|---|---|---|---|---|
| NF-01 | 可用性：マルチAZ | System Node Group × 2AZ、Karpenter AZ分散、EFS Multi-AZ | `kubectl get nodes -o wide` でAZ確認 | 全ノードが2AZ以上に分散していること |
| NF-02 | RTO：4時間以内 | EFSバックアップ（AWS Backup）、Karpenter自動復旧 | DRテスト（四半期） | EFS全量リストアが4時間以内に完了すること |
| NF-03 | RPO：1時間以内 | EFS日次バックアップ、Secrets Managerバージョン管理 | バックアップ復元テスト | 最大1時間前の状態に復元できること |
| NF-04 | 通信暗号化（TLS 1.2以上） | ALB TLS設定、VPC Endpoint | SSL Labs / aws alb describe-listeners | TLS 1.2以上のみ許可されていること |
| NF-05 | 保存データ暗号化 | KMS CMK（全ストレージ） | `aws efs describe-file-systems` 等でEncryption確認 | 全リソースでKMS暗号化が有効なこと |
| NF-06 | 認証（ユーザ） | Cognito | ログインテスト | 正規ユーザのみログイン可能なこと |
| NF-07 | 認証（AWSアクセス） | Pod Identity | `aws sts get-caller-identity`（Pod内実行） | ApplicationRoleのARNが返却されること |
| NF-08 | 最小権限 | IAMポリシー（ApplicationRole等） | IAM Access Analyzer | 未使用権限がないこと |
| NF-09 | 監査ログ365日保持 | CloudWatch Logs（Retention 365日） | `aws logs describe-log-groups` | 全LogGroupのRetentionが365日であること |
| NF-10 | Pod可用性（ローリング更新） | PDB（minAvailable: 1）、HPA | ローリングアップデート実施 | 更新中もサービス断なしに完了すること |
| NF-11 | Egress制限 | Private-AppサブネットのRoute Table（デフォルトルートなし）、NetworkPolicy | `kubectl exec` でcurl外部URLを実行 | インターネットへの直接通信が拒否されること |
| NF-12 | イメージセキュリティ | ECR Enhanced Scanning、cosign署名 | CIパイプライン実行ログ | CRITICAL/HIGH脆弱性でCIがFailすること |

---

# 12. Kubernetes設計詳細

## 12.1 Deployment標準設定

全Deploymentに以下を必須とする。Gatekeeperで強制する（[6.5節](#65-admissionコントローラ)参照）。

```yaml
spec:
  replicas: 2  # 最低2レプリカ（本番）
  template:
    spec:
      nodeSelector:
        node-role: workload  # System Nodeへの誤配置防止
      securityContext:
        runAsNonRoot: true
        seccompProfile:
          type: RuntimeDefault
      containers:
        - name: app
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities:
              drop: [ALL]
          resources:
            requests:
              cpu: 250m
              memory: 512Mi
            limits:
              cpu: 1000m
              memory: 1024Mi
```

## 12.2 PodDisruptionBudget

全サービスにPDBを設定し、ノード退避・ローリング更新時の可用性を確保する。

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: app-api-pdb
  namespace: app-prod
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app: app-api
```

## 12.3 HorizontalPodAutoscaler

全APIサービスにHPAを設定する。

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: app-api-hpa
  namespace: app-prod
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: app-api
  minReplicas: 2
  maxReplicas: 10
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70
```

---

# 13. CloudFormation構成

## 13.1 管理方針

AWSリソースはすべてCloudFormationで構築・管理する。

**CloudFormation管理対象：**

VPC、VPC Endpoint、EKS、Managed Node Group、EFS、KMS、Secrets Manager、EventBridge、Lambda、CloudWatch、IAM、CloudTrail、Cognito、ECR、CodeBuild、CodePipeline、AWS Budgets

**Kubernetes Manifest管理対象（GitOps / ArgoCD管理）：**

Namespace、Deployment、Service、Ingress、NetworkPolicy、ArgoCD Application、Karpenter NodePool / EC2NodeClass、Pod Identity Association（kubectl apply）

## 13.2 スタック構成と依存関係

```
01-network       VPC / Subnet / Route / SG / VPC Endpoint / ALB
    ↓
02-security      KMS / IAM / Pod Identity Role / CloudTrail
    ↓
03-storage       EFS / Backup / Secrets Manager
    ↓
04-eks           EKS Cluster / Managed Node Group / Addon / Pod Identity
    ↓
05-monitoring    CloudWatch / LogGroup / Alarm / Dashboard / SNS / AWS Budgets
    ↓
06-cicd          CodeBuild / CodePipeline / ECR

07-identity      Cognito / Lambda / EventBridge（独立デプロイ可）
```

## 13.3 スタック詳細

### 01-network

| リソース | Logical ID | Type |
|---|---|---|
| VPC | Vpc | AWS::EC2::VPC |
| Public Subnet（AZ1/2） | PublicSubnetAz1/2 | AWS::EC2::Subnet |
| Private System Subnet（AZ1/2） | PrivateSystemSubnetAz1/2 | AWS::EC2::Subnet |
| Private App Subnet（AZ1/2） | PrivateAppSubnetAz1/2 | AWS::EC2::Subnet |
| Private Endpoint Subnet（AZ1/2） | PrivateEndpointSubnetAz1/2 | AWS::EC2::Subnet |
| Internet Gateway | InternetGateway | AWS::EC2::InternetGateway |
| NAT Gateway（AZ1/2） | NatGatewayAz1/2 | AWS::EC2::NatGateway |
| Public Route Table | PublicRouteTable | AWS::EC2::RouteTable |
| Private System Route Table | PrivateSystemRouteTable | AWS::EC2::RouteTable |
| Private App Route Table | PrivateAppRouteTable | AWS::EC2::RouteTable |
| ALB | ApplicationLoadBalancer | AWS::ElasticLoadBalancingV2::LoadBalancer |
| HTTPS Listener | AlbHttpsListener | AWS::ElasticLoadBalancingV2::Listener |
| HTTP Listener | AlbHttpListener | AWS::ElasticLoadBalancingV2::Listener |

Interface VPC Endpoints（Private-Endpointサブネット配置）：

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

Gateway VPC Endpoints：

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
| EFS Access Point（upload） | EfsAccessPointUpload |
| EFS Access Point（share） | EfsAccessPointShare |
| EFS Access Point（batch） | EfsAccessPointBatch |
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
| Pod Identity Agent Addon | PodIdentityAddon |

### 05-monitoring

| リソース | 内容 |
|---|---|
| CloudWatch LogGroups | /eks/prod/application・system・audit |
| Container Insights | `aws eks update-addon` で有効化 |
| CloudWatch Alarms | アラート一覧（[9.3節](#93-アラート設計重要度分類)）に対応 |
| CloudWatch Dashboards | cluster-overview・application・cicd・cost |
| SNS Topic | アラート通知先 |
| AWS Budgets | 月次予算・80%/100%通知 |

### 06-cicd

| リソース | Logical ID |
|---|---|
| ECR Repository | ApplicationRepository |
| ECR Lifecycle Policy | （ApplicationRepositoryに付属） |
| CodeBuild Project | ApplicationBuildProject |
| CodePipeline | ApplicationPipeline |

### 07-identity

Cognito UserPool、Lambda（ユーザ変更通知）、EventBridge Rule

## 13.4 パラメータ設計

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

  BudgetAmountUSD:
    Type: Number
    Description: 月次予算（USD）
```

## 13.5 スタック間の値連携

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

## 13.6 ディレクトリ構成

```
infra/
└─ templates/
    ├─ 01-network/
    │   ├─ vpc.yaml
    │   ├─ subnet.yaml
    │   ├─ route.yaml
    │   ├─ nacl.yaml
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
    │   ├─ loggroups.yaml
    │   ├─ alarms.yaml
    │   ├─ dashboards.yaml
    │   ├─ sns.yaml
    │   └─ budgets.yaml
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

# 14. 命名規約・タグ付け

## 14.1 AWSリソース命名

```
<system>-<env>-<resource>

例：
  sample-prd-vpc
  sample-prd-eks
  sample-prd-ecr
  sample-prd-efs
```

## 14.2 環境識別子

| 環境 | 識別子 |
|---|---|
| 開発 | dev |
| 検証 | stg |
| 本番 | prd |

## 14.3 Secrets Manager命名

```
/<env>/<system>/<service>/<name>

例：/prod/sample/app/db-password
```

## 14.4 CloudWatch LogGroup命名

```
/eks/<env>/application
/eks/<env>/system
/eks/<env>/audit
```

## 14.5 必須タグ

全AWSリソースに以下のタグを付与する。CloudFormationのDefaultTagsで自動付与する（[14.6節](#146-タグ付け自動化)参照）。

| Key | Value例 | 必須 |
|---|---|---|
| System | sample | ✓ |
| Environment | prd | ✓ |
| ManagedBy | CloudFormation | ✓ |
| Owner | platform-team | ✓ |
| CostCenter | xxxx | ✓ |
| Project | eks-platform | - |

## 14.6 タグ付け自動化

### CloudFormation DefaultTags

スタックレベルでDefaultTagsを設定し、スタック内の全リソースへ自動的にタグを付与する。

```yaml
# samconfig.toml または deploy時のオプション
[default.deploy.parameters]
tags = "System=sample Environment=prd ManagedBy=CloudFormation Owner=platform-team"
```

または CloudFormation Console / CLI でスタック作成時に指定する：

```bash
aws cloudformation deploy \
  --stack-name sample-prd-network \
  --template-file templates/01-network/vpc.yaml \
  --tags System=sample Environment=prd ManagedBy=CloudFormation Owner=platform-team CostCenter=xxxx
```

### タグ準拠チェック（CIジョブ）

CloudFormationデプロイ前に以下のツールでテンプレートを検査する。

```yaml
# CodeBuild buildspec.yml（cfn-lint + checkov）
phases:
  build:
    commands:
      # CloudFormation linting
      - cfn-lint templates/**/*.yaml

      # セキュリティ・タグ準拠チェック
      - checkov -d templates/ \
          --check CKV_AWS_111,CKV_AWS_119 \
          --compact

      # 必須タグ確認（カスタムスクリプト）
      - python scripts/check-required-tags.py templates/
```

必須タグチェックスクリプト例：

```python
# scripts/check-required-tags.py
import sys, glob, yaml

REQUIRED_TAGS = {"System", "Environment", "ManagedBy", "Owner", "CostCenter"}

errors = []
for path in glob.glob(f"{sys.argv[1]}/**/*.yaml", recursive=True):
    with open(path) as f:
        tpl = yaml.safe_load(f)
    for name, res in tpl.get("Resources", {}).items():
        props = res.get("Properties", {})
        tags = {t["Key"] for t in props.get("Tags", [])}
        missing = REQUIRED_TAGS - tags
        if missing:
            errors.append(f"{path} / {name}: missing tags {missing}")

if errors:
    print("\n".join(errors))
    sys.exit(1)
```

---

# 15. 運用手順・Runbook

## 15.1 Runbook一覧

| Runbook ID | タイトル | 重要度 | 推定対応時間 |
|---|---|---|---|
| RB-001 | NodeNotReady対応 | P0 | 30分 |
| RB-002 | EKS API Server障害対応 | P0 | 60分 |
| RB-003 | CrashLoopBackOff対応 | P1 | 30分 |
| RB-004 | ArgoCD同期失敗対応 | P1 | 30分 |
| RB-005 | リソース高使用率対応 | P2 | 60分 |
| RB-006 | EFS障害・容量不足対応 | P1 | 60分 |
| RB-007 | ECR脆弱性検出対応 | P1 | 翌営業日中 |

---

## RB-001: NodeNotReady対応

**トリガー:** CloudWatch Alarm → NodeNotReady

### 診断手順

```bash
# 1. Nodeの状態確認
kubectl get nodes
kubectl describe node <NODE_NAME>

# 2. NodeのCondition確認
kubectl get node <NODE_NAME> -o jsonpath='{.status.conditions[*]}'

# 3. Nodeの直近イベント確認
kubectl get events --field-selector involvedObject.name=<NODE_NAME> --sort-by='.lastTimestamp'

# 4. EC2の状態確認（Karpenter NodeはEC2から確認）
aws ec2 describe-instances \
  --filters "Name=tag:karpenter.sh/nodepool,Values=general" \
  --query 'Reservations[*].Instances[*].[InstanceId,State.Name,PrivateIpAddress]'
```

### 対応フロー

```
NodeNotReady確認
  ├─ EC2インスタンス自体が停止 → Karpenterが自動で新規Node作成（通常は自動復旧）
  │   └─ 5分待機後も復旧しない → EC2コンソールで状態確認・手動でNode削除
  │
  ├─ Kubelet停止（EC2は起動中） → Node再起動
  │   └─ kubectl drain → EC2再起動 → kubectl uncordon
  │
  └─ ネットワーク障害 → SG / VPC Endpoint / Route Tableを確認
```

```bash
# Node手動削除（Karpenterが自動でプロビジョニング）
kubectl delete node <NODE_NAME>

# Node退避（Podを安全に移動させてから削除）
kubectl drain <NODE_NAME> --ignore-daemonsets --delete-emptydir-data
kubectl delete node <NODE_NAME>
```

**エスカレーション:** 30分以内に復旧しない場合、P0エスカレーションでリードSREに連絡。

---

## RB-003: CrashLoopBackOff対応

**トリガー:** CloudWatch Alarm → CrashLoopBackOff

### 診断手順

```bash
# 1. 対象Podの特定
kubectl get pods -A | grep CrashLoopBackOff

# 2. Podの詳細確認
kubectl describe pod <POD_NAME> -n <NAMESPACE>

# 3. ログ確認（現在・直前のコンテナ）
kubectl logs <POD_NAME> -n <NAMESPACE>
kubectl logs <POD_NAME> -n <NAMESPACE> --previous

# 4. イベント確認
kubectl get events -n <NAMESPACE> --sort-by='.lastTimestamp' | tail -20
```

### 主な原因と対応

| 原因 | 確認ポイント | 対応 |
|---|---|---|
| 設定ミス（環境変数・Secret） | ログのエラーメッセージ | SecretProviderClass・Deployment設定を確認 |
| リソース不足（OOMKill） | `describe pod` の `Last State: OOMKilled` | resource limitsを調整 |
| イメージ起動失敗 | `ErrImagePull` / `ImagePullBackOff` | ECR認証・イメージタグを確認 |
| アプリケーションバグ | ログのスタックトレース | 開発チームへエスカレーション、前バージョンにロールバック |

```bash
# ロールバック（ArgoCD）
argocd app rollback app-api <REVISION_NUMBER>

# または直接
kubectl rollout undo deployment/app-api -n app-prod
```

---

## RB-004: ArgoCD同期失敗対応

**トリガー:** CloudWatch Alarm → ArgoCD Sync Failed

### 診断手順

```bash
# ArgoCD CLIでアプリ状態確認
argocd app list
argocd app get app-api

# 同期ログ確認
argocd app logs app-api

# Kubernetesイベント確認
kubectl get events -n app-prod --sort-by='.lastTimestamp'
```

### 主な原因と対応

| 原因 | 確認ポイント | 対応 |
|---|---|---|
| Manifestの構文エラー | argocd app get のエラーメッセージ | GitOpsリポジトリのPR修正 |
| リソース権限不足 | ArgoCD Roleの権限 | IAM / RBAC確認 |
| クラスタ接続不可 | `argocd cluster list` | EKS API Server・SG確認 |
| CRD未インストール | Unknown resource type | 必要なAddonを先にインストール |

```bash
# 強制同期（--force は慎重に）
argocd app sync app-api
argocd app sync app-api --force
```

---

## RB-006: EFS障害・容量不足対応

**トリガー:** CloudWatch Alarm → EFS容量超過 / EFSマウントエラー

### 診断手順

```bash
# EFS状態確認
aws efs describe-file-systems \
  --file-system-id <EFS_ID> \
  --region ap-northeast-1

# マウントターゲット確認
aws efs describe-mount-targets \
  --file-system-id <EFS_ID>

# Pod内でマウント状態確認
kubectl exec -n app-prod -it <POD_NAME> -- df -h
```

### 容量不足対応

EFSはElastic Throughputのため容量上限はないが、コスト管理のためにCloudWatchメトリクス（`StorageBytes`）を監視する。容量アラートが発火した場合は古いファイルの整理を実施する。

---

## RB-007: ECR脆弱性検出対応

**トリガー:** ECR Enhanced Scanning → CRITICAL/HIGH脆弱性

### 対応フロー

```
ECR脆弱性アラート（CRITICAL/HIGH）
  ↓
対象イメージとCVE番号を特定
  ↓
ベースイメージのアップデート対応か確認
  ├─ ベースイメージ起因 → 最新ベースイメージに更新してCIリビルド
  └─ アプリ依存ライブラリ起因 → 開発チームで対象パッケージを更新
  ↓
修正イメージをECRにPush
  ↓
ArgoCDで新イメージをデプロイ
  ↓
脆弱性スキャン結果を再確認
```

```bash
# 脆弱性詳細確認
aws ecr describe-image-scan-findings \
  --repository-name app-prod \
  --image-id imageTag=<TAG> \
  --region ap-northeast-1 \
  | jq '.imageScanFindings.findings[] | select(.severity=="CRITICAL" or .severity=="HIGH")'
```

---

## 15.2 定期メンテナンス計画

| 作業 | 頻度 | 担当 | 手順 |
|---|---|---|---|
| EKSバージョンアップグレード | 年2回 | Platform SRE | 別途Upgrade Runbook |
| KMSキー棚卸し | 年次 | Platform SRE | 使用中キーの確認・不要キーの削除申請 |
| EFSリストアテスト | 四半期 | Platform SRE | バックアップVaultから検証EFSにリストア・I/O確認 |
| DRテスト | 年次 | Platform SRE + Dev | 本番相当環境でRTO/RPOを検証 |
| IAM権限レビュー | 四半期 | Platform SRE + Security | IAM Access Analyzerで未使用権限を検出・削除 |
| コスト最適化レビュー | 月次 | Platform SRE | resource requestsの適正化・Spot利用率確認 |
| タグ準拠チェック | 月次 | Platform SRE | CloudFormationデプロイ時CI確認 |

---

# 16. 実装完了判定基準

各項目について「検証コマンド」と「期待結果」を明記する。全項目がPASSした時点で実装完了とする。

## 16.1 基盤

### [INFRA-01] VPC・Subnet・VPC Endpoint作成

```bash
# Subnetの確認
aws ec2 describe-subnets \
  --filters "Name=tag:System,Values=sample" \
  --query 'Subnets[*].[SubnetId,CidrBlock,AvailabilityZone,Tags[?Key==`Name`].Value|[0]]' \
  --output table

# Private-AppサブネットのRoute Tableにデフォルトルートがないことを確認
aws ec2 describe-route-tables \
  --filters "Name=tag:Name,Values=sample-prd-private-app-rtb" \
  --query 'RouteTables[*].Routes'
```

**期待結果:** Private-Appのルートテーブルに `0.0.0.0/0` エントリが存在しないこと。

### [INFRA-02] EKSクラスタ起動

```bash
kubectl get nodes -o wide
kubectl get pods -n kube-system
```

**期待結果:** 全Nodeが `Ready`、system addonが `Running` であること。

### [INFRA-03] Pod Identity有効化

```bash
aws eks list-pod-identity-associations \
  --cluster-name sample-prd-eks \
  --region ap-northeast-1

kubectl exec -n app-prod -it <POD_NAME> -- \
  aws sts get-caller-identity
```

**期待結果:** `UserId` が `ApplicationRole` の ARN であること。

## 16.2 セキュリティ

### [SEC-01] KMS暗号化確認

```bash
# EFS暗号化確認
aws efs describe-file-systems \
  --query 'FileSystems[*].[FileSystemId,Encrypted,KmsKeyId]' \
  --output table

# Secrets Manager暗号化確認
aws secretsmanager describe-secret \
  --secret-id /prod/sample/app/db-password \
  --query 'KmsKeyId'
```

**期待結果:** 全リソースで `Encrypted: true`、KmsKeyIdが空でないこと。

### [SEC-02] Egress制限確認

```bash
# Workload Podからのインターネット通信が拒否されることを確認
kubectl exec -n app-prod -it <POD_NAME> -- \
  curl -m 5 https://example.com
```

**期待結果:** `curl: (28) Connection timed out` または `curl: (6) Could not resolve host` が返ること（ルーティングなし）。

### [SEC-03] Secrets Manager経由のシークレット取得

```bash
# SecretProviderClassが正しくマウントされていることを確認
kubectl exec -n app-prod -it <POD_NAME> -- \
  ls /mnt/secrets/

kubectl exec -n app-prod -it <POD_NAME> -- \
  cat /mnt/secrets/db-password
```

**期待結果:** シークレット値がファイルとして読み取れること。

### [SEC-04] イメージスキャン・署名確認

```bash
# CIパイプラインのビルドログでスキャン結果を確認
aws codebuild batch-get-builds \
  --ids <BUILD_ID> \
  --query 'builds[*].phases'

# cosign署名検証
cosign verify \
  --certificate-identity-regexp=".*" \
  --certificate-oidc-issuer="https://token.actions.githubusercontent.com" \
  <ACCOUNT_ID>.dkr.ecr.ap-northeast-1.amazonaws.com/app-prod:<TAG>
```

**期待結果:** スキャンでCRITICAL/HIGHが0件、署名検証がPASSすること。

## 16.3 CI/CD

### [CICD-01] CodeBuildビルド成功

```bash
aws codebuild list-builds-for-project \
  --project-name sample-prd-app-build \
  --query 'ids[0]'

aws codebuild batch-get-builds \
  --ids <BUILD_ID> \
  --query 'builds[*].[buildStatus,currentPhase]'
```

**期待結果:** `buildStatus: SUCCEEDED`

### [CICD-02] ArgoCD自動同期

```bash
argocd app list
argocd app get app-api --show-params
```

**期待結果:** `Sync Status: Synced`、`Health Status: Healthy`

## 16.4 監視

### [MON-01] Container Insightsログ確認

```bash
aws logs describe-log-groups \
  --log-group-name-prefix /aws/containerinsights \
  --query 'logGroups[*].[logGroupName,retentionInDays]'
```

**期待結果:** Container InsightsのLogGroupが存在し、retentionInDaysが `365` であること。

### [MON-02] アラーム動作確認（テスト）

```bash
# テスト用にアラーム状態を手動で変更
aws cloudwatch set-alarm-state \
  --alarm-name "sample-prd-node-not-ready" \
  --state-value ALARM \
  --state-reason "Test"

# SNS通知の受信を確認（メール or PagerDuty）
# 確認後、アラームをリセット
aws cloudwatch set-alarm-state \
  --alarm-name "sample-prd-node-not-ready" \
  --state-value OK \
  --state-reason "Test complete"
```

**期待結果:** 指定した通知先（Slack/PagerDuty）にアラートが到達すること。

## 16.5 バックアップ

### [BKP-01] EFSバックアップ設定確認

```bash
aws backup list-backup-plans \
  --query 'BackupPlansList[*].[BackupPlanName,BackupPlanId]'

aws backup get-backup-plan \
  --backup-plan-id <PLAN_ID>
```

**期待結果:** 日次バックアップルールが存在し、RetentionPeriodが35日以上であること。

---

# 付録：主要運用コマンド

## A. EKS操作

```bash
# kubeconfig取得（Windows PowerShell）
aws eks update-kubeconfig `
  --name sample-prd-eks `
  --region ap-northeast-1

# 全Pod確認
kubectl get pods -A

# 特定NamespaceのPod詳細
kubectl get pods -n app-prod -o wide

# ノード確認（AZ・インスタンスタイプ確認）
kubectl get nodes -L topology.kubernetes.io/zone,node.kubernetes.io/instance-type
```

## B. ArgoCD操作

```bash
# Application一覧
argocd app list

# 手動同期
argocd app sync app-api

# ロールバック
argocd app rollback app-api <REVISION>
```

## C. Karpenter操作

```bash
# Karpenter管理ノード確認
kubectl get nodes -l karpenter.sh/nodepool

# NodePool状態確認
kubectl get nodepools
kubectl get ec2nodeclasses
```

## D. トラブルシュート

```bash
# Pod内でShell実行
kubectl exec -n app-prod -it <POD_NAME> -- /bin/sh

# Podログ確認（直前のコンテナ含む）
kubectl logs <POD_NAME> -n app-prod --previous

# Kubernetesイベント確認
kubectl get events -n app-prod --sort-by='.lastTimestamp' | tail -20

# Secrets Manager シークレット取得確認（Pod内）
aws secretsmanager get-secret-value \
  --secret-id /prod/sample/app/db-password \
  --region ap-northeast-1
```

