---
title: AWS EKS CI/CD 基盤 システムアーキテクチャ仕様書
date: 2026-06-09
status: Draft
---

> 本書は要求仕様と実装コードの間に位置する**唯一の設計仕様書**である。

| 項目 | 内容 |
|---|---|
| 文書種別 | システムアーキテクチャ仕様書 |
| 作成日 | 2026-06-09 |
| ステータス | Draft |
| 対象システム | AWS EKS + CodeBuild + ArgoCD 基盤 |
| 作業端末 | Windows / PowerShell / SSO 認証済み |

---

## 目次

1. [文書概要](#1-文書概要)
2. [システム概要](#2-システム概要)
3. [アーキテクチャ方針](#3-アーキテクチャ方針)
4. [業務シーケンス](#4-業務シーケンス)
5. [サービス選定](#5-サービス選定)
6. [論理アーキテクチャ](#6-論理アーキテクチャ)
7. [ネットワーク設計](#7-ネットワーク設計)
8. [EKS 設計](#8-eks-設計)
9. [CI 設計（CodeBuild）](#9-ci-設計codebuild)
10. [CD 設計（ArgoCD）](#10-cd-設計argocd)
11. [認証・認可設計](#11-認証認可設計)
12. [ECR 設計](#12-ecr-設計)
13. [実装設計](#13-実装設計)
14. [非機能要件](#14-非機能要件)
15. [受入条件](#15-受入条件)
16. [未定義事項](#16-未定義事項)

---


# 1. 文書概要


## 1.1 目的

本書は AWS 上でコンテナアプリケーションを安全・安定的に運用するための基盤設計を定義する。

以下の基盤を実現する。

- コンテナアプリケーション実行基盤（EKS）
- CI/CD 基盤（CodeBuild + ArgoCD）
- コンテナイメージ管理基盤（ECR）
- ID・権限管理基盤（Pod Identity）
- 閉域ネットワーク基盤（VPC Endpoint）

> 💡 **なぜ** 本書は要求仕様と実装コードの間に位置する唯一の設計仕様書である。要求仕様の「何を実現するか」を受け取り、実装者が「どう作るか」を判断できる粒度まで落とし込む。AWS サービスの説明書ではなく、本システム固有の設計判断を記録することに価値がある。


## 1.2 スコープ


### 対象

- AWS インフラ（VPC、EC2、IAM 等）
- Kubernetes 基盤（EKS クラスター、ノード構成）
- CI/CD パイプライン（CodeBuild、ArgoCD）
- 認証・認可（Pod Identity、IAM）

### 対象外

- アプリケーション内部ロジック
- DB スキーマ設計
- フロントエンド実装

# 2. システム概要


## 2.1 構成概要

本システムは以下の構成要素で成り立つ。インターネット経由の通信は行わず、全 AWS サービスへのアクセスは VPC Endpoint 経由とする。

```
VPC (Private Network)
  │
  ├─ [CI パイプライン]
  │    CodeBuild → ECR Push → GitOps Repo 更新
  │
  ├─ [CD パイプライン]
  │    ArgoCD（System Node）→ EKS へ反映
  │
  ├─ [アプリ実行]
  │    EKS Workload Node（Karpenter 管理）
  │    └ ECR から Pull（VPC Endpoint 経由）
  │
  └─ [管理アクセス]
       踏み台 EC2 → kubectl → EKS API（Private）
```


## 2.2 システム責務

| コンポーネント | 責務 | 管理方式 |
|---|---|---|
| EKS | コンテナアプリケーション実行 | AWS Managed |
| CodeBuild | Docker Build / ECR Push / GitOps Repo 更新 | AWS Managed |
| ECR | コンテナイメージ保管・配布 | AWS Managed |
| ArgoCD | GitOps による継続的デプロイ | Self-managed（EKS 上） |
| Karpenter | ワークロードノード自動プロビジョニング | Self-managed（EKS 上） |
| 踏み台 EC2 | kubectl 操作・管理コマンド実行 | Self-managed |
| VPC Endpoint | AWS サービスへの閉域接続 | AWS Managed |
| Pod Identity | Pod への IAM 権限付与 | AWS Managed（EKS アドオン） |


# 3. アーキテクチャ方針

本章の設計方針は全コンポーネントの設計判断の根拠となる。個別コンポーネント設計でこれらと矛盾が生じた場合は本章を優先する。


## 3.1 Managed First

可能な限り AWS Managed Service を利用する。

> 💡 **なぜ** EKS アドオン（VPC CNI、CoreDNS、kube-proxy、Pod Identity Agent）は AWS が管理するため、Kubernetes バージョンアップ時のパッチ適用が不要になる。ノードの OS パッチも Managed Node Group で自動化できる。自前でデーモンを管理すると運用コストが非線形に増加するため、AWS に管理を委ねられる部分はすべて委ねる。


## 3.2 Zero Trust Network（閉域通信）

AWS サービスとの通信は VPC Endpoint 経由のみとする。NAT Gateway を置かない。

> 💡 **なぜ** NAT Gateway を経由するとインターネット上に通信が出る。ECR・STS・Secrets Manager 等の機密データを扱う通信がインターネットを経由することは、セキュリティポリシー上許容しない。またコスト面でも NAT Gateway のデータ転送費は VPC Endpoint より高くなるケースが多い。

> ⚠️ **注意** VPC Endpoint を使う場合、エンドポイントの Security Group で 443/tcp のインバウンドを VPC CIDR から許可する必要がある。また ECR の場合 ecr.api と ecr.dkr の両方が必要であり、S3 Gateway Endpoint も併用しなければ Layer イメージの取得に失敗する。


## 3.3 GitOps（Kubernetes リソースの変更は Git 経由のみ）

EKS へのリソース適用は ArgoCD 経由のみとする。kubectl apply の直接実行は障害対応時の一時的措置に限定する。

> 💡 **なぜ** 直接 kubectl apply を行うと Git との乖離が生じ、次回 ArgoCD Sync 時に巻き戻りが発生する。変更履歴が Git にのみ残るため、監査証跡が明確になる。ロールバックも Git revert で実現できる。


## 3.4 Zero Secret（AccessKey 不使用）

Pod から AWS サービスを呼ぶ際は Pod Identity を使い、Static な AccessKey を一切使用しない。

```
Pod
 └─ Pod Identity Agent（EKS アドオン）
      └─ STS（VPC Endpoint 経由）
           └─ 一時クレデンシャル
                └─ ECR / Secrets Manager 等
```

> 💡 **なぜ** IRSA（IAM Roles for Service Accounts）は OIDC Provider の設定が複雑で、トークンの有効期限管理が煩雑になる。Pod Identity は EKS アドオンが全て処理するため設定が単純であり、AWS が推奨する新しい方式である。AccessKey をコードや環境変数に埋め込むアンチパターンを構造的に排除できる。


## 3.5 ノード分離（System / Workload）

Kubernetes のシステム Pod（ArgoCD、Karpenter 等）とアプリケーション Pod のノードを分離する。

> 💡 **なぜ** Karpenter がワークロードの需要に応じてノードをプロビジョニング・削除するとき、システム Pod が同居していると Karpenter 自身の Pod が evict される危険がある。また、アプリの負荷によってシステム Pod のリソースが枯渇することを防ぐ。System Node Group は常時 2 台以上を維持することで可用性を確保する。


## 3.6 IaC First（CloudFormation を単一の真実源とする）

AWS リソースは CloudFormation テンプレートで管理する。マネジメントコンソールからの手動作成は禁止する。

> 💡 **なぜ** 手動作成は再現性がなく、削除・再作成時にパラメータが不明になる。CloudFormation であれば Drift Detection により意図しない変更を検知できる。スタック分割設計については 13 章で定義する。


# 4. 業務シーケンス

本章が本仕様書のコアである。各シーケンスを実現するために後続章のリソース設計が存在する。


## 4.1 コンテナビルド・プッシュシーケンス（CI）


### 目的

開発者が Git Push した後、コンテナイメージを自動的にビルドして ECR に Push する。


### フロー

```
Developer
 └─ Git Push（feature → main）
      └─ CodeBuild トリガー（Webhook or EventBridge）
           └─ buildspec.yml 実行
                ├─ docker build
                ├─ ECR Get Login（VPC Endpoint 経由、Pod Identity で認証）
                ├─ docker push（ECR / ecr.dkr VPC Endpoint 経由）
                └─ GitOps リポジトリ更新
                     └─ kustomize edit set image <ECR_URI>:<IMAGE_TAG>
                          └─ git commit & push → ArgoCD が検知
```


### IMAGE_TAG 規則

Git commit SHA の先頭 8 文字を IMAGE_TAG とする（例: `a1b2c3d4`）。`latest` タグは使用しない。

> 💡 **なぜ** latest タグはどのイメージを指しているかが不明確になり、ロールバック時に問題が起きる。commit SHA であればソースコードとイメージの対応が一意に確定する。


## 4.2 デプロイシーケンス（CD）


### 目的

GitOps リポジトリへの Push をトリガーに、ArgoCD が EKS へ自動でデプロイする。


### フロー

```
GitOps リポジトリ（image tag 更新済み）
 └─ ArgoCD（System Node 上）が差分を検知（ポーリング、デフォルト 3 分）
      └─ Sync 開始
           ├─ ECR から新 image を pull（ecr.dkr VPC Endpoint 経由）
           ├─ Rolling Update（Pod を順次入れ替え）
           └─ Sync 完了 → ArgoCD の Healthy 状態へ遷移
```


### Sync ポリシー

| 設定 | 値 | 理由 |
|---|---|---|
| automated.prune | true | Git から削除されたリソースを EKS からも削除する |
| automated.selfHeal | true | 手動変更を自動的に Git の状態に戻す |
| syncOptions CreateNamespace | true | Namespace を事前作成しなくてよい |


## 4.3 ワークロードスケールシーケンス（Karpenter）


### 目的

アプリケーションの負荷に応じて EC2 ノードを自動的にプロビジョニング・削除する。


### スケールアウトフロー

```
Pod スケジュール不可（リソース不足）
 └─ kube-scheduler が Pending 状態にする
      └─ Karpenter がイベントを検知
           └─ NodeClaim を作成
                └─ EC2NodeClass に基づき EC2 インスタンス起動
                     └─ ノードが Ready 状態 → Pod がスケジュール
```


### スケールインフロー

```
ノードの使用率低下を Karpenter が検知
 └─ consolidationPolicy: WhenEmptyOrUnderutilized 評価
      └─ Pod を他ノードへ移動（Evict）
           └─ EC2 インスタンス終了
```


## 4.4 管理者操作シーケンス


### 目的

Windows 作業端末から EKS への kubectl 操作を安全に実行する。


### フロー

```
Windows PC
 └─ aws sso login（ブラウザ認証）
      └─ PowerShell: aws eks update-kubeconfig
           └─ SSM Session Manager でトンネル確立
                └─ 踏み台 EC2 上で kubectl コマンド実行
                     └─ EKS API（Private Endpoint）へ到達
```

> ⚠️ **注意** EKS API は EndpointPublicAccess: false のため、踏み台 EC2 を経由しなければ到達できない。Windows PC から直接 kubectl を実行する場合は SSM Port Forwarding でプロキシを通す必要がある。


# 5. サービス選定


## 5.1 コンテナオーケストレーション

| 候補 | 採否 | 理由 |
|---|---|---|
| EKS | ✅ 採用 | Kubernetes 標準 API。ポータビリティが高く、エコシステムが豊富 |
| ECS | ❌ 不採用 | AWS 独自 API のため移行コストが高い。Kubernetes スキルセットが活かせない |
| EC2 直接 | ❌ 不採用 | コンテナオーケストレーション機能を自前実装することになり運用負荷が大 |

> ✅ **決定** EKS を採用する。


## 5.2 ノードオートスケーラー

| 候補 | 採否 | 理由 |
|---|---|---|
| Karpenter | ✅ 採用 | スケール速度が速く（秒単位）、インスタンスタイプの柔軟な選択とコスト最適化ができる |
| Cluster Autoscaler | ❌ 不採用 | Auto Scaling Group ベースで柔軟性が低い。スケール完了まで数分かかる |

> ✅ **決定** Karpenter を採用する。System Pod は Managed Node Group（常時 2 台）で保護し、アプリは Karpenter ノードで動かす。


## 5.3 CD ツール

| 候補 | 採否 | 理由 |
|---|---|---|
| ArgoCD | ✅ 採用 | GitOps ネイティブ。UI が充実しており Sync 状態の可視化が容易 |
| Flux | ❌ 不採用 | CLI 中心で可視化が弱い。チームへの学習コストが高い |
| CodeDeploy | ❌ 不採用 | Kubernetes ネイティブではなく、マニフェスト管理が煩雑になる |

> ✅ **決定** ArgoCD を採用する。System Node Group 上で稼働させ、Pod Identity で必要最小限の AWS 権限を付与する。


## 5.4 権限管理方式

| 候補 | 採否 | 理由 |
|---|---|---|
| Pod Identity | ✅ 採用 | EKS アドオンが全処理。設定が単純で AWS 推奨の最新方式 |
| IRSA | ❌ 不採用 | OIDC Provider 管理が複雑。Pod Identity の登場で非推奨扱い |
| Node IAM Role | ❌ 不採用 | ノード上の全 Pod が同一権限を持つため最小権限原則に反する |
| AccessKey 埋め込み | ❌ 不採用 | セキュリティポリシー違反。ローテーション管理が困難 |

> ✅ **決定** Pod Identity を採用する。IRSA は使用しない。


# 6. 論理アーキテクチャ


## 6.1 レイヤー構成

```
┌────────────────────────────────────────────┐
│  CI/CD Layer                               │
│  CodeBuild（Build/Push）+ ArgoCD（Deploy）  │
├────────────────────────────────────────────┤
│  Platform Layer（System Node Group）        │
│  ArgoCD, Karpenter, Metrics Server         │
├────────────────────────────────────────────┤
│  Application Layer（Karpenter Node）        │
│  Application Pods（各 Namespace）           │
├────────────────────────────────────────────┤
│  Network Layer                             │
│  VPC, Subnet, VPC Endpoint, Security Group │
└────────────────────────────────────────────┘
```


## 6.2 Namespace 設計

| Namespace | 用途 | 配置ノード |
|---|---|---|
| kube-system | Kubernetes システムコンポーネント | System Node Group |
| argocd | ArgoCD コンポーネント | System Node Group |
| karpenter | Karpenter コンポーネント | System Node Group |
| `<app-name>` | アプリケーション Pod | Karpenter Node |


# 7. ネットワーク設計


## 7.1 VPC 構成

| リソース | 設定値 | 備考 |
|---|---|---|
| VPC CIDR | 10.0.0.0/16 | 65,536 アドレス |
| Private Subnet × 2 | 10.0.1.0/24, 10.0.2.0/24 | EKS ノード、CodeBuild、踏み台配置 |
| Internet Gateway | 不使用 | 外部通信しないため不要 |
| NAT Gateway | 不使用 | VPC Endpoint で代替 |
| DNS Support | true | VPC Endpoint の Private DNS 解決に必須 |
| DNS Hostnames | true | VPC Endpoint の Private DNS 解決に必須 |

> ⚠️ **注意** DNS Support と DNS Hostnames を両方有効にしないと VPC Endpoint の Private DNS が機能しない。ECR へのアクセスで「endpoint resolution failed」が発生する。


## 7.2 VPC Endpoint 一覧

| サービス | タイプ | 用途 | Private DNS |
|---|---|---|---|
| ecr.api | Interface | ECR API（認証・リポジトリ操作） | 有効 |
| ecr.dkr | Interface | ECR Docker レジストリ（image pull/push） | 有効 |
| s3 | Gateway | ECR レイヤーデータ / CodeBuild アーティファクト | N/A |
| eks | Interface | EKS API | 有効 |
| ec2 | Interface | EC2 操作（Karpenter） | 有効 |
| sts | Interface | Pod Identity / STS | 有効 |
| codebuild | Interface | CodeBuild | 有効 |
| logs | Interface | CloudWatch Logs | 有効 |
| ssm | Interface | SSM（踏み台接続） | 有効 |
| ssmmessages | Interface | SSM Session Manager | 有効 |
| ec2messages | Interface | SSM 経由 EC2 メッセージング | 有効 |
| autoscaling | Interface | Karpenter による Auto Scaling | 有効 |

> ⚠️ **注意** ecr.api だけでは不十分。ecr.dkr と s3 Gateway Endpoint の両方がなければ docker pull が失敗する（Layer は S3 に格納されているため）。


## 7.3 Security Group 設計

| SG 名 | 適用対象 | インバウンド | アウトバウンド |
|---|---|---|---|
| endpoint-sg | VPC Endpoint | 443/tcp from VPC CIDR | なし |
| cluster-sg | EKS クラスター | ノード SG から 443/tcp | 全許可 |
| node-sg | EKS ノード | cluster-sg から全ポート | 全許可（VPC 内） |
| bastion-sg | 踏み台 EC2 | なし（SSM のみ） | endpoint-sg への 443 |
| build-sg | CodeBuild | なし | endpoint-sg への 443 |


## 7.4 CFn テンプレート（VPC Endpoints 抜粋）

```yaml
# スタック: 01-network.yaml (抜粋)
Resources:
  VpcEndpointEcrApi:
    Type: AWS::EC2::VPCEndpoint
    Properties:
      VpcId: !Ref VpcId
      ServiceName: !Sub com.amazonaws.${AWS::Region}.ecr.api
      VpcEndpointType: Interface
      SubnetIds: !Ref PrivateSubnetIds
      SecurityGroupIds: [!Ref EndpointSG]
      PrivateDnsEnabled: true

  VpcEndpointEcrDkr:
    Type: AWS::EC2::VPCEndpoint
    Properties:
      VpcId: !Ref VpcId
      ServiceName: !Sub com.amazonaws.${AWS::Region}.ecr.dkr
      VpcEndpointType: Interface
      SubnetIds: !Ref PrivateSubnetIds
      SecurityGroupIds: [!Ref EndpointSG]
      PrivateDnsEnabled: true

  VpcEndpointS3:           # ECR Layer 取得に必須
    Type: AWS::EC2::VPCEndpoint
    Properties:
      VpcId: !Ref VpcId
      ServiceName: !Sub com.amazonaws.${AWS::Region}.s3
      VpcEndpointType: Gateway
      RouteTableIds: !Ref PrivateRouteTableIds
```


# 8. EKS 設計


## 8.1 クラスター設計

| 設定項目 | 値 | 理由 |
|---|---|---|
| Kubernetes バージョン | 1.31 | LTS 相当の最新安定版 |
| API サーバーアクセス | Private Only | インターネットからの到達を禁止（3.2 方針） |
| 認証モード | API モード | ConfigMap 管理を排除。アクセスエントリ API で管理 |
| Pod Identity | EKS アドオン | IRSA を使わない（5.4 決定事項） |
| EKS アドオン | vpc-cni / coredns / kube-proxy / pod-identity-agent | マネージドアドオンで運用コスト削減 |


## 8.2 ノード設計


### System Managed Node Group

| 設定項目 | 値 |
|---|---|
| 用途 | ArgoCD、Karpenter 等のシステム Pod |
| インスタンスタイプ | m5.large（2vCPU / 8GB） |
| 台数 | 常時 2 台（Min:2 / Max:4） |
| Taint | dedicated=system:NoSchedule |
| Label | role=system |
| IMDSv2 | 必須（HttpTokens: required） |

> 💡 **なぜ** System Node Group にシステム Pod を Taint で固定することで、Karpenter がワークロードノードを全台削除しても ArgoCD・Karpenter 自身は稼働し続ける。常時 2 台を異なる AZ に配置することで AZ 障害にも耐性を持つ。


### Karpenter Workload Node

| 設定項目 | 値 |
|---|---|
| 用途 | アプリケーション Pod |
| インスタンスタイプ | m5系・c5系（NodePool で指定） |
| 容量タイプ | On-Demand |
| AMI | Amazon Linux 2023（al2023@latest） |
| Consolidation | WhenEmptyOrUnderutilized（1 分後） |
| IMDSv2 | 必須（httpTokens: required） |


## 8.3 CFn テンプレート（EKS Cluster 抜粋）

```yaml
# スタック: 05-eks-cluster.yaml (抜粋)
Resources:
  EksCluster:
    Type: AWS::EKS::Cluster
    Properties:
      Name: !Ref ClusterName
      Version: "1.31"
      ResourcesVpcConfig:
        SubnetIds: !Ref PrivateSubnetIds
        SecurityGroupIds: [!Ref ClusterSG]
        EndpointPrivateAccess: true
        EndpointPublicAccess: false   # インターネット到達禁止
      AccessConfig:
        AuthenticationMode: API       # ConfigMap 不使用
      RoleArn: !GetAtt EksClusterRole.Arn

  EksPodIdentityAddon:
    Type: AWS::EKS::Addon
    DependsOn: EksCluster
    Properties:
      ClusterName: !Ref EksCluster
      AddonName: eks-pod-identity-agent
      ResolveConflicts: OVERWRITE

  SystemNodeGroup:
    Type: AWS::EKS::Nodegroup
    DependsOn: EksPodIdentityAddon
    Properties:
      ClusterName: !Ref EksCluster
      NodegroupName: system-ng
      NodeRole: !GetAtt NodeRole.Arn
      Subnets: !Ref PrivateSubnetIds
      InstanceTypes: [m5.large]
      ScalingConfig: { MinSize: 2, MaxSize: 4, DesiredSize: 2 }
      Labels: { role: system }
      Taints:
        - Key: dedicated
          Value: system
          Effect: NO_SCHEDULE
```


# 9. CI 設計（CodeBuild）


## 9.1 パイプライン概要

| フェーズ | 処理内容 |
|---|---|
| pre_build | IMAGE_TAG 生成（commit SHA 8 桁）、ECR ログイン（VPC Endpoint 経由） |
| build | docker build、docker push（ECR へ） |
| post_build | GitOps リポジトリ clone、kustomize でイメージタグ更新、git push |


## 9.2 CodeBuild プロジェクト設定

| 設定項目 | 値 | 理由 |
|---|---|---|
| ビルド環境 | Amazon Linux 2023 managed image | 標準環境で再現性を確保 |
| 特権モード | 有効 | docker build に必須 |
| VPC 設定 | EKS と同じ Private Subnet | ECR・STS へ VPC Endpoint 経由でアクセス |
| ログ | CloudWatch Logs | VPC Endpoint（logs）経由で転送 |
| IAM 権限 | ECR Push / GitOps Repo Push / Logs | 最小権限。Pod Identity ではなく CodeBuild サービスロール |


## 9.3 buildspec.yaml（骨格）

```yaml
# buildspec.yaml
version: 0.2
phases:
  pre_build:
    commands:
      - IMAGE_TAG=$(echo $CODEBUILD_RESOLVED_SOURCE_VERSION | cut -c1-8)
      - aws ecr get-login-password --region $AWS_DEFAULT_REGION \
          | docker login --username AWS --password-stdin $ECR_REPO
  build:
    commands:
      - docker build -t $ECR_REPO:$IMAGE_TAG .
      - docker push $ECR_REPO:$IMAGE_TAG
  post_build:
    commands:
      - git clone $GITOPS_REPO_URL gitops
      - cd gitops/overlays/prod
      - kustomize edit set image $ECR_REPO:$IMAGE_TAG
      - git config user.email "codebuild@system"
      - git config user.name "CodeBuild"
      - git commit -am "ci: update image tag to $IMAGE_TAG"
      - git push
# 補足: git push の認証は CodeBuild サービスロールに
#       CodeCommit への認証情報が付与される前提
```


## 9.4 CFn テンプレート（CodeBuild 抜粋）

```yaml
# スタック: 09-codebuild.yaml (抜粋)
Resources:
  BuildProject:
    Type: AWS::CodeBuild::Project
    Properties:
      Name: !Sub ${AppName}-build
      ServiceRole: !GetAtt BuildRole.Arn
      Environment:
        Type: LINUX_CONTAINER
        ComputeType: BUILD_GENERAL1_SMALL
        Image: aws/codebuild/amazonlinux2-x86_64-standard:5.0
        PrivilegedMode: true
        EnvironmentVariables:
          - Name: ECR_REPO
            Value: !Sub ${AWS::AccountId}.dkr.ecr.${AWS::Region}.amazonaws.com/${AppName}
          - Name: GITOPS_REPO_URL
            Value: !Ref GitOpsRepoUrl
      Source:
        Type: CODECOMMIT
        Location: !Sub https://git-codecommit.${AWS::Region}.amazonaws.com/v1/repos/${RepoName}
      VpcConfig:
        VpcId: !Ref VpcId
        Subnets: !Ref PrivateSubnetIds
        SecurityGroupIds: [!Ref BuildSG]
      LogsConfig:
        CloudWatchLogs:
          Status: ENABLED
          GroupName: !Sub /codebuild/${AppName}
```


# 10. CD 設計（ArgoCD）


## 10.1 インストール方針

Helm で ArgoCD を System Node Group 上にインストールする。Pod には Taint Toleration と NodeSelector を付与して System Node Group に固定する。


## 10.2 argocd-values.yaml（骨格）

```yaml
# argocd-values.yaml（Helm values）
global:
  tolerations:
    - key: dedicated
      value: system
      operator: Equal
      effect: NoSchedule
  nodeSelector:
    role: system

server:
  service:
    type: ClusterIP        # 外部 LB 不使用
  extraArgs:
    - --insecure           # TLS は上位レイヤーで終端

configs:
  params:
    server.insecure: true
  cm:
    timeout.reconciliation: 180s   # ポーリング間隔（デフォルト 3 分）
```


## 10.3 Application マニフェスト

```yaml
# argocd-application.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: ${APP_NAME}
  namespace: argocd
spec:
  project: default
  source:
    repoURL: ${GITOPS_REPO_URL}
    targetRevision: main
    path: overlays/prod
  destination:
    server: https://kubernetes.default.svc
    namespace: ${APP_NAME}
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```


## 10.4 Git リポジトリ構成

```
gitops-repo/
├── base/
│   ├── deployment.yaml
│   ├── service.yaml
│   └── kustomization.yaml
└── overlays/
    ├── dev/
    │   └── kustomization.yaml   # image tag は CI が更新
    └── prod/
        └── kustomization.yaml   # image tag は CI が更新
```


# 11. 認証・認可設計


## 11.1 Pod Identity 設計方針

各 ServiceAccount に対して IAM ロールを 1:1 で対応させる。IAM ロールは CloudFormation で管理し、Pod Identity Association も CFn リソースで作成する。

> 💡 **なぜ** 1 Pod = 1 ServiceAccount = 1 IAM Role の対応関係を維持することで、どの Pod がどの AWS サービスにアクセスできるかが設計書から一意に追跡できる。IAM ロールを共有すると、一方の権限が漏れた際に他方にも影響する。


## 11.2 Pod Identity 対応表

| コンポーネント | Namespace | ServiceAccount | 必要な IAM 権限 |
|---|---|---|---|
| Karpenter | karpenter | karpenter | EC2 起動/終了、EKS NodeClaim 管理 |
| ArgoCD Server | argocd | argocd-server | 最小限（Git アクセスは SSH Key） |
| Application | `<app>` | `<app>-sa` | アプリ固有（Secrets Manager 等） |


## 11.3 IAM ロール CFn（Pod Identity Association 抜粋）

```yaml
# スタック: 10-pod-identity.yaml (抜粋)
Resources:
  KarpenterControllerRole:
    Type: AWS::IAM::Role
    Properties:
      RoleName: !Sub KarpenterController-${ClusterName}
      AssumeRolePolicyDocument:
        Version: "2012-10-17"
        Statement:
          - Effect: Allow
            Principal:
              Service: pods.eks.amazonaws.com
            Action:
              - sts:AssumeRole
              - sts:TagSession      # Pod Identity で必須
      # Policies は Karpenter 公式の CloudFormation を参照

  KarpenterPodIdentityAssociation:
    Type: AWS::EKS::PodIdentityAssociation
    Properties:
      ClusterName: !Ref ClusterName
      Namespace: karpenter
      ServiceAccount: karpenter
      RoleArn: !GetAtt KarpenterControllerRole.Arn
```


## 11.4 管理者 EKS アクセス権限

SSO ユーザーに EKS Access Entry を作成し、kubectl アクセス権を付与する。ConfigMap（aws-auth）は使用しない。

```bash
# 踏み台 EC2 から実行
aws eks create-access-entry \
  --cluster-name ${CLUSTER_NAME} \
  --principal-arn arn:aws:iam::${ACCOUNT_ID}:role/${SSO_ROLE_NAME} \
  --type STANDARD

aws eks associate-access-policy \
  --cluster-name ${CLUSTER_NAME} \
  --principal-arn arn:aws:iam::${ACCOUNT_ID}:role/${SSO_ROLE_NAME} \
  --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy \
  --access-scope type=cluster
```


# 12. ECR 設計

| 設定項目 | 値 | 理由 |
|---|---|---|
| リポジトリタイプ | Private | 外部公開不要 |
| ScanOnPush | 有効 | CVE を自動検出 |
| 暗号化 | KMS | デフォルト AES256 より強固 |
| ライフサイクルポリシー | 最新 20 イメージを保持 | ストレージコスト削減 |
| imagePullSecrets | 不使用 | ノードの IAM ロール（ECR ReadOnly）で Pull |

> ⚠️ **注意** ECR への通信は ecr.api + ecr.dkr + s3 の 3 Endpoint が揃って初めて成功する。docker pull が "no such host" になる場合は ecr.dkr の Private DNS を確認する。


# 13. 実装設計


## 13.1 CloudFormation スタック構成

| No | スタック名 | 主なリソース | 依存 |
|---|---|---|---|
| 01 | network | VPC / Subnet / RouteTable / VPC Endpoint | なし |
| 02 | security-groups | 各 Security Group | 01 |
| 03 | iam-base | Cluster Role / Node Role / CodeBuild Role | なし |
| 04 | ecr | ECR リポジトリ | なし |
| 05 | eks-cluster | EKS Cluster / アドオン | 01, 02, 03 |
| 06 | managed-ng | System Managed Node Group | 05 |
| 07 | karpenter-iam | Karpenter Controller Role / Node Role | 03 |
| 08 | bastion | 踏み台 EC2 / Instance Profile | 01, 02, 03 |
| 09 | codebuild | CodeBuild Project | 01, 02, 03, 04 |
| 10 | pod-identity | Pod Identity Associations | 05, 03 |


## 13.2 デプロイ手順（PowerShell）

```powershell
# Windows PowerShell / SSO 認証済み前提
$Region  = "ap-northeast-1"
$Prefix  = "myapp"
$VpcCidr = "10.0.0.0/16"

# 1. ネットワーク
aws cloudformation deploy `
  --template-file .\cfn\01-network.yaml `
  --stack-name "$Prefix-network" `
  --parameter-overrides VpcCidr=$VpcCidr `
  --region $Region

# 2. スタック出力を取得して次スタックのパラメータに使う
$netOut = aws cloudformation describe-stacks `
  --stack-name "$Prefix-network" `
  --query "Stacks[0].Outputs" `
  --output json | ConvertFrom-Json
$VpcId = ($netOut | Where-Object OutputKey -eq VpcId).OutputValue

# 3. 以降も同様に順次デプロイ
# (06 Managed Node Group まで完了後、踏み台 EC2 で kubeconfig 設定)
# aws eks update-kubeconfig --name <cluster> --region $Region

# 4. Helm で Karpenter / ArgoCD インストール（踏み台上で実行）
helm upgrade --install karpenter oci://public.ecr.aws/karpenter/karpenter `
  --namespace karpenter --create-namespace `
  --set settings.clusterName=<cluster-name> `
  -f karpenter-values.yaml
```


## 13.3 Karpenter YAML 仕様

```yaml
# karpenter-nodepool.yaml
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: workload-pool
spec:
  template:
    metadata:
      labels: { role: workload }
    spec:
      nodeClassRef:
        group: karpenter.k8s.aws
        kind: EC2NodeClass
        name: workload-class
      requirements:
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["on-demand"]
        - key: kubernetes.io/arch
          operator: In
          values: ["amd64"]
  limits:
    cpu: 100
  disruption:
    consolidationPolicy: WhenEmptyOrUnderutilized
    consolidateAfter: 1m
---
apiVersion: karpenter.k8s.aws/v1
kind: EC2NodeClass
metadata:
  name: workload-class
spec:
  amiSelectorTerms:
    - alias: al2023@latest
  role: KarpenterNodeRole-<cluster-name>
  subnetSelectorTerms:
    - tags: { karpenter.sh/discovery: <cluster-name> }
  securityGroupSelectorTerms:
    - tags: { karpenter.sh/discovery: <cluster-name> }
  metadataOptions:
    httpTokens: required
```


# 14. 非機能要件

| 区分 | 要件 | 実現方法 |
|---|---|---|
| 可用性 | System Pod は AZ 障害に耐性を持つ | System Node Group を 2AZ に分散（常時 2 台） |
| セキュリティ | インターネット経由通信なし | NAT GW 不使用。全通信を VPC Endpoint 経由 |
| セキュリティ | Static AccessKey 不使用 | Pod Identity / CodeBuild Service Role |
| セキュリティ | IMDSv2 必須 | 全 EC2 / EKS ノードで HttpTokens: required |
| セキュリティ | EKS API は Private のみ | EndpointPublicAccess: false |
| 監査 | リソース変更履歴 | CloudFormation / Git による変更管理 |
| コスト | ワークロードノードのコスト最適化 | Karpenter consolidation（未使用ノードを自動削除） |
| 再現性 | 環境の再構築が可能 | CloudFormation 全リソース管理。手動作成禁止 |


# 15. 受入条件

以下が全て成功することをもって本基盤の構築完了とする。


| No | 確認項目 | 確認方法 | 判定基準 |
|---|---|---|---|
| 1 | EKS クラスター作成 | `kubectl get nodes` | System Node 2 台以上が Ready |
| 2 | Pod Identity 動作 | テスト Pod から STS コール | 一時クレデンシャル取得成功 |
| 3 | ECR イメージ Pull | テスト Pod 起動 | ECR イメージが VPC Endpoint 経由で Pull される |
| 4 | CodeBuild CI | Git Push → ビルドトリガー | ECR Push と GitOps Repo 更新が成功 |
| 5 | ArgoCD CD | GitOps Repo 更新 → Sync | EKS 上の Pod が新イメージで再起動 |
| 6 | Karpenter スケール | Pending Pod を発生させる | ノードが 60 秒以内に Ready になる |
| 7 | 踏み台アクセス | SSM Session Manager で接続 | SSH 不使用で kubectl 実行成功 |
| 8 | インターネット遮断 | 踏み台から `curl ifconfig.me` | タイムアウト（外部到達不可） |


# 16. 未定義事項

以下はコード実装前に確定が必要な事項である。確定次第、本書を更新すること。


| No | 事項 | 影響範囲 | 期限 |
|---|---|---|---|
| 1 | Git リポジトリサービスの選定（CodeCommit / GitHub 等） | CI 設計（9章） | 実装前 |
| 2 | ArgoCD UI へのアクセス方法（kubectl port-forward / 内部 ALB） | CD 設計（10章） | 実装前 |
| 3 | Secrets 管理方式（Secrets Manager + External Secrets Operator 等） | 11章追加 | 実装前 |
| 4 | Karpenter NodePool のインスタンスタイプ制約 | 13章 Karpenter YAML | 実装前 |
| 5 | 監視・ロギング方式（CloudWatch Container Insights / Prometheus） | 新章追加 | Phase2 |
| 6 | ArgoCD SSO 設定（SAML / OIDC） | 11章追加 | Phase2 |
| 7 | アプリ用 Namespace・ResourceQuota 設計 | 6.2章追加 | Phase2 |
