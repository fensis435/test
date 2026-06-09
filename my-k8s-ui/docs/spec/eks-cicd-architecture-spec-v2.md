---
title: AWS EKS CI/CD 基盤 システムアーキテクチャ仕様書
date: 2026-06-09
status: Draft
---

> 本書は要求仕様と実装コードの間に位置する**唯一の設計仕様書**である。

| 項目 | 内容 |
| --- | --- |
| 文書種別 | システムアーキテクチャ仕様書 |
| 作成日 | 2026-06-09 |
| ステータス | Draft |
| 対象システム | AWS EKS + CodeBuild + ArgoCD 基盤 |
| 作業端末 | Windows / PowerShell / SSO 認証済み |

## 目次

**レビューア向け（1〜15章）**

1. [文書概要](#1-文書概要)
2. [システム概要](#2-システム概要)
3. [設計方針](#3-設計方針)
4. [アーキテクチャ決定記録 ADR](#4-アーキテクチャ決定記録-adr)
5. [システムシーケンス](#5-システムシーケンス)
6. [論理アーキテクチャ](#6-論理アーキテクチャ)
7. [ネットワーク設計](#7-ネットワーク設計)
8. [EKS 設計](#8-eks-設計)
9. [CI/CD 設計](#9-cicd-設計)
10. [認証・認可設計](#10-認証認可設計)
11. [ECR 設計](#11-ecr-設計)
12. [監視設計](#12-監視設計)
13. [運用設計](#13-運用設計)
14. [非機能要件](#14-非機能要件)
15. [受入条件](#15-受入条件)

**実装者向け（16章〜）**

16. [実装設計](#16-実装設計)
17. [未定義事項](#17-未定義事項)

**Appendix**

- [A. CFn サンプル抜粋](#appendix-a-cfn-サンプル抜粋)
- [B. buildspec.yaml](#appendix-b-buildspecyaml)
- [C. Helm values 骨格](#appendix-c-helm-values-骨格)
- [D. Kubernetes マニフェスト骨格](#appendix-d-kubernetes-マニフェスト骨格)

---


# 1. 文書概要


## 1.1 目的

本書は AWS 上でコンテナアプリケーションを安全・安定的に運用するための基盤を設計する。

以下の基盤を実現する。

- コンテナアプリケーション実行基盤（EKS）
- CI/CD 基盤（CodeBuild + ArgoCD）
- コンテナイメージ管理基盤（ECR）
- ID・権限管理基盤（Pod Identity）
- 閉域ネットワーク基盤（VPC Endpoint）
- 監視基盤（CloudWatch）

> 💡 **なぜ**　本書は要求仕様と実装コードの間に位置する唯一の設計仕様書である。AWS サービスの説明書ではなく、本システム固有の設計判断と「なぜそうするか」を記録することに価値がある。レビューアは 1〜15 章で設計判断を検証し、実装者は 16 章以降でコードに落とし込む。


## 1.2 スコープ


### 対象

- AWS インフラ（VPC、EC2、IAM 等）
- Kubernetes 基盤（EKS クラスター、ノード構成）
- CI/CD パイプライン（CodeBuild、ArgoCD）
- 認証・認可（Pod Identity、IAM）
- 監視（CloudWatch）

### 対象外

- アプリケーション内部ロジック
- DB スキーマ設計
- フロントエンド実装

# 2. システム概要


## 2.1 構成概要

本システムは以下の構成で成り立つ。インターネット経由の通信は行わず、全 AWS サービスへのアクセスは VPC Endpoint 経由とする。

```
VPC (Private Network)
  │
  ├─ [CI パイプライン]
  │    CodeBuild ──→ ECR Push ──→ GitOps Repo 更新
  │
  ├─ [CD パイプライン]
  │    ArgoCD（System Node）──→ EKS へ反映
  │
  ├─ [アプリ実行]
  │    EKS Workload Node（Karpenter 管理）
  │    └── ECR から Pull（VPC Endpoint 経由）
  │
  ├─ [監視]
  │    CloudWatch（Logs / Metrics / Alarms）
  │
  └─ [管理アクセス]
       踏み台 EC2 ──→ kubectl ──→ EKS API（Private）
```


## 2.2 システム責務

| コンポーネント | 責務 | 管理方式 |
| --- | --- | --- |
| EKS | コンテナアプリケーション実行 | AWS Managed |
| CodeBuild | Docker Build / ECR Push / GitOps Repo 更新 | AWS Managed |
| ECR | コンテナイメージ保管・配布 | AWS Managed |
| ArgoCD | GitOps による継続的デプロイ | Self-managed（EKS 上） |
| Karpenter | ワークロードノード自動プロビジョニング | Self-managed（EKS 上） |
| CloudWatch | メトリクス・ログ収集、アラート | AWS Managed |
| 踏み台 EC2 | kubectl 操作・管理コマンド実行 | Self-managed |
| VPC Endpoint | AWS サービスへの閉域接続 | AWS Managed |
| Pod Identity | Pod への IAM 権限付与 | AWS Managed（EKS アドオン） |


# 3. 設計方針

本章の方針は全コンポーネントの設計判断の根拠となる。個別設計でこれらと矛盾が生じた場合は本章を優先する。個別のサービス選定理由は 4 章（ADR）に記録する。


## 3.1 Managed First

可能な限り AWS Managed Service を利用する。

> 💡 **なぜ**　EKS アドオン（VPC CNI、CoreDNS、kube-proxy、Pod Identity Agent）は AWS が管理するため、Kubernetes バージョンアップ時のパッチ適用が不要になる。自前でデーモンを管理すると運用コストが非線形に増加する。


## 3.2 閉域通信（Zero Trust Network）

AWS サービスとの通信は VPC Endpoint 経由のみとする。NAT Gateway を置かない。

> 💡 **なぜ**　ECR・STS 等の機密データを扱う通信がインターネットを経由することはセキュリティポリシー上許容しない。また NAT Gateway のデータ転送コストも排除できる。


## 3.3 GitOps

EKS へのリソース適用は ArgoCD 経由のみとする。`kubectl apply` の直接実行は障害対応時の一時的措置に限定する。

> 💡 **なぜ**　直接 kubectl apply を行うと Git との乖離が生じ、次回 ArgoCD Sync 時に巻き戻りが発生する。変更履歴が Git にのみ残るため監査証跡が明確になる。


## 3.4 Zero Secret（AccessKey 不使用）

Pod から AWS サービスを呼ぶ際は Pod Identity を使い、Static な AccessKey を一切使用しない。

> 💡 **なぜ**　AccessKey をコードや環境変数に埋め込むアンチパターンを構造的に排除する。Pod Identity は EKS アドオンが全て処理するため設定が単純であり、AWS が推奨する最新方式である。


## 3.5 ノード分離（System / Workload）

システム Pod（ArgoCD、Karpenter 等）とアプリケーション Pod のノードを分離する。

> 💡 **なぜ**　Karpenter がワークロードノードを削除するとき、システム Pod が同居していると Karpenter 自身が evict される危険がある。System Node Group を常時 2 台以上維持することで AZ 障害耐性も確保する。


## 3.6 IaC First

AWS リソースは CloudFormation テンプレートで管理する。マネジメントコンソールからの手動作成を禁止する。

> 💡 **なぜ**　手動作成は再現性がない。CloudFormation の Drift Detection で意図しない変更を検知できる。スタック分割設計は 16 章で定義する。


# 4. アーキテクチャ決定記録 ADR

本章はアーキテクチャ上の重要な決定を記録する。将来の担当者が「なぜこの選択をしたか」を追跡できるようにすることが目的である。


## ADR-001　コンテナ基盤

| 項目 | 内容 |
| --- | --- |
| 採用 | EKS |
| 不採用 | ECS、EC2 直接 |


### 理由

- Kubernetes 標準 API を採用することでポータビリティを確保する
- 本システムが採用する GitOps（ArgoCD）および Karpenter は Kubernetes ネイティブであり、ECS では利用できない
- 将来のマルチクラウド移行時に ECS では再実装が必要になる


## ADR-002　ノードオートスケーラー

| 項目 | 内容 |
| --- | --- |
| 採用 | Karpenter |
| 不採用 | Cluster Autoscaler |


### 理由

- Cluster Autoscaler は Auto Scaling Group ベースでインスタンスタイプの柔軟な選択ができず、スケール完了まで数分かかる
- Karpenter は Pending Pod を直接監視して秒単位でノードをプロビジョニングし、使用率が低下したノードを自動統合することでコストを最適化する
- System Node Group（Managed Node Group）と組み合わせることで、システム Pod の可用性を損なわずにワークロードをスケールできる


## ADR-003　継続的デプロイ

| 項目 | 内容 |
| --- | --- |
| 採用 | ArgoCD |
| 不採用 | Flux、CodePipeline Deploy |


### 理由

- GitOps を一貫して採用するため、Kubernetes ネイティブな CD ツールを選択する
- ArgoCD は UI が充実しており Sync 状態の可視化が容易で、障害時の切り戻し判断が迅速にできる
- Flux は CLI 中心で可視化が弱く、チームへの学習コストが高い
- CodePipeline Deploy は Kubernetes ネイティブではなく、マニフェスト管理が煩雑になる


## ADR-004　AWS 認証方式（Pod → AWS サービス）

| 項目 | 内容 |
| --- | --- |
| 採用 | Pod Identity（EKS アドオン） |
| 不採用 | IRSA、AccessKey 埋め込み、Node IAM Role |


### 理由

- AccessKey 埋め込みはローテーション管理が困難でセキュリティポリシー違反
- Node IAM Role はノード上の全 Pod が同一権限を持つため最小権限原則に反する
- IRSA は OIDC Provider の管理が複雑でトークンの有効期限管理が煩雑。Pod Identity の登場により非推奨扱いとなっている
- Pod Identity は EKS アドオンが全処理を担うため設定が単純。`sts:TagSession` アクションと `pods.eks.amazonaws.com` の trust policy のみで動作する


## ADR-005　ネットワーク閉域化

| 項目 | 内容 |
| --- | --- |
| 採用 | VPC Endpoint（Interface / Gateway）+ NAT Gateway 不使用 |
| 不採用 | NAT Gateway 経由のインターネットアクセス |


### 理由

- セキュリティポリシーにより、ECR・STS 等の機密通信をインターネット経由にすることを禁止している
- NAT Gateway のデータ転送費は VPC Endpoint より高コストになるケースが多い
- VPC Endpoint を利用すれば AWS サービスへの通信が AWS バックボーン内で完結し、経路の予測可能性が高い


## ADR-006　EKS API エンドポイント

| 項目 | 内容 |
| --- | --- |
| 採用 | Private Only（EndpointPublicAccess: false） |
| 不採用 | Public アクセス有効 |


### 理由

- EKS API をインターネットに公開する必要がない（踏み台 EC2 経由でアクセスする）
- Public エンドポイントを無効化することで、インターネットからのクラスター操作を構造的に排除できる


# 5. システムシーケンス

本章が本仕様書のコアである。各シーケンスを実現するために後続章のリソース設計が存在する。CloudFormation を見ても分からない「コンポーネント間の相互作用」を記録することに価値がある。


## 5.1 コンテナビルド・プッシュシーケンス（CI）


### 目的

開発者の Git Push をトリガーに、コンテナイメージを自動ビルドして ECR に格納し、GitOps リポジトリのイメージタグを更新する。


### フロー

```
Developer
 └─▶ git push（feature → main）
       │
       └─▶ CodeBuild トリガー（EventBridge）
             │
             ├─▶ ECR ログイン取得
             │     └─ STS（VPC Endpoint 経由）で一時クレデンシャル発行
             │
             ├─▶ docker build
             │
             ├─▶ docker push ──▶ ECR（ecr.dkr VPC Endpoint 経由）
             │
             └─▶ GitOps リポジトリ更新
                   └─ kustomize edit set image <ECR_URI>:<IMAGE_TAG>
                        └─ git commit & push
```


### IMAGE_TAG 規則

Git commit SHA の先頭 8 文字を IMAGE_TAG とする（例: `a1b2c3d4`）。`latest` タグは使用しない。

> 💡 **なぜ**　`latest` タグはどのイメージを指しているか不明確になりロールバック時に問題が起きる。commit SHA であればソースコードとイメージの対応が一意に確定し、障害時の原因追跡が容易になる。


## 5.2 デプロイシーケンス（CD）


### 目的

GitOps リポジトリへの Push をトリガーに、ArgoCD が EKS へ自動デプロイする。開発者はデプロイ操作を一切行わない。


### フロー

```
GitOps リポジトリ（image tag 更新済み）
 └─▶ ArgoCD がポーリングで差分を検知（デフォルト 3 分）
       │
       └─▶ Sync 開始
             │
             ├─▶ ECR から新 image を pull
             │     └─ ecr.dkr VPC Endpoint 経由
             │
             ├─▶ Rolling Update
             │     └─ Pod を順次入れ替え（旧 Pod → 新 Pod）
             │
             └─▶ Sync 完了 → ArgoCD: Healthy 状態へ遷移
```


### Sync ポリシー

| 設定 | 値 | 理由 |
| --- | --- | --- |
| automated.prune | true | Git から削除されたリソースを EKS からも削除する |
| automated.selfHeal | true | 手動変更を自動的に Git の状態に戻す |
| syncOptions CreateNamespace | true | Namespace を事前作成しなくてよい |


## 5.3 ワークロードスケールシーケンス（Karpenter）


### 目的

アプリケーションの負荷変化に対して、EC2 ノードを自動的にプロビジョニング・削除してコストと性能を最適化する。


### スケールアウト

```
Pod が Pending 状態（リソース不足）
 └─▶ Karpenter がイベントを検知
       └─▶ NodeClaim を作成
             └─▶ EC2NodeClass に基づき EC2 インスタンス起動
                   └─▶ ノードが Ready → Pod がスケジュール
                         （目標: 60 秒以内）
```


### スケールイン（コスト最適化）

```
ノード使用率の低下を Karpenter が検知
 └─▶ consolidationPolicy: WhenEmptyOrUnderutilized を評価
       └─▶ Pod を他ノードへ移動（Evict）
             └─▶ EC2 インスタンス終了
                   （consolidateAfter: 1m 後に実行）
```


## 5.4 Pod 起動・AWS サービス認証シーケンス（Pod Identity）


### 目的

Pod が起動する際に、AccessKey を使わずに AWS サービスへのアクセス権を動的に取得する。


### フロー

```
Pod 起動リクエスト
 └─▶ EKS が Pod Identity Agent に通知
       └─▶ Pod Identity Agent → STS（VPC Endpoint 経由）
             └─▶ sts:AssumeRole + sts:TagSession
                   └─▶ 一時クレデンシャル発行
                         └─▶ Pod の環境変数に自動インジェクト
                               └─▶ Pod → AWS サービス呼び出し
                                     （ECR pull / Secrets Manager 等）
```

> 💡 **なぜ**　AccessKey をコードや環境変数に静的に埋め込む場合、漏洩時の影響範囲が広く、ローテーション管理も困難になる。Pod Identity では一時クレデンシャルが自動的に更新されるため、漏洩リスクと運用負荷を同時に削減できる。


## 5.5 管理者操作シーケンス


### 目的

Windows 作業端末から EKS への kubectl 操作を、SSH を使わずに安全に実行する。


### フロー

```
Windows PC
 └─▶ aws sso login（ブラウザ認証）
       └─▶ PowerShell: aws eks update-kubeconfig
             └─▶ SSM Session Manager でトンネル確立
                   └─▶ 踏み台 EC2 上で kubectl 実行
                         └─▶ EKS API（Private Endpoint）へ到達
```

> ⚠️ **注意**　EKS API は EndpointPublicAccess: false のため踏み台 EC2 を経由しなければ到達できない。Windows PC から直接 kubectl を実行する場合は SSM Port Forwarding でプロキシを通す必要がある。


# 6. 論理アーキテクチャ


## 6.1 レイヤー構成

```
┌──────────────────────────────────────────────┐
│  CI/CD Layer                                 │
│  CodeBuild（Build/Push）+ ArgoCD（Deploy）    │
├──────────────────────────────────────────────┤
│  Platform Layer  ← System Node Group         │
│  ArgoCD / Karpenter / Metrics Server         │
├──────────────────────────────────────────────┤
│  Application Layer  ← Karpenter Node         │
│  Application Pods（各 Namespace）             │
├──────────────────────────────────────────────┤
│  Observability Layer                         │
│  CloudWatch Logs / Metrics / Alarms          │
├──────────────────────────────────────────────┤
│  Network Layer                               │
│  VPC / Subnet / VPC Endpoint / SG            │
└──────────────────────────────────────────────┘
```


## 6.2 Namespace 設計

| Namespace | 用途 | 配置ノード | 備考 |
| --- | --- | --- | --- |
| kube-system | Kubernetes システムコンポーネント | System Node Group | EKS マネージドアドオン |
| argocd | ArgoCD コンポーネント | System Node Group | Taint Toleration 付与 |
| karpenter | Karpenter コンポーネント | System Node Group | Taint Toleration 付与 |
| `<app-name>` | アプリケーション Pod | Karpenter Node | 1 アプリ 1 Namespace |


## 6.3 責務分離の原則

システム Pod とアプリ Pod を Taint/Toleration で分離することで以下を実現する。

- Karpenter がワークロードノードを全台削除しても ArgoCD・Karpenter 自身は稼働し続ける
- アプリの負荷スパイクがシステム Pod のリソースに影響しない
- System Node Group の 2 台常時稼働により AZ 障害時も管理機能を維持する

# 7. ネットワーク設計


## 7.1 VPC 構成

| リソース | 設定値 | 備考 |
| --- | --- | --- |
| VPC CIDR | 10.0.0.0/16 | 65,536 アドレス |
| Private Subnet × 2 | 10.0.1.0/24 / 10.0.2.0/24 | EKS ノード・CodeBuild・踏み台を配置 |
| Internet Gateway | 不使用 | 外部通信しないため不要 |
| NAT Gateway | 不使用 | VPC Endpoint で代替（ADR-005） |
| DNS Support | true | VPC Endpoint Private DNS 解決に必須 |
| DNS Hostnames | true | VPC Endpoint Private DNS 解決に必須 |

> ⚠️ **注意**　DNS Support と DNS Hostnames を両方有効にしないと VPC Endpoint の Private DNS が機能しない。ECR へのアクセスで "endpoint resolution failed" が発生する。


## 7.2 VPC Endpoint 一覧

| サービス | タイプ | 用途 |
| --- | --- | --- |
| ecr.api | Interface | ECR API（認証・リポジトリ操作） |
| ecr.dkr | Interface | ECR Docker レジストリ（image pull/push） |
| s3 | Gateway | ECR レイヤーデータ取得（ECR の Layer は S3 格納） |
| eks | Interface | EKS API |
| ec2 | Interface | EC2 操作（Karpenter がノードを操作） |
| sts | Interface | Pod Identity / 一時クレデンシャル発行 |
| codebuild | Interface | CodeBuild |
| logs | Interface | CloudWatch Logs |
| ssm | Interface | SSM（踏み台接続） |
| ssmmessages | Interface | SSM Session Manager |
| ec2messages | Interface | SSM 経由 EC2 メッセージング |
| autoscaling | Interface | Karpenter による Auto Scaling 操作 |

> ⚠️ **注意**　`ecr.api` だけでは不十分。`ecr.dkr` と `s3` Gateway Endpoint の両方がなければ docker pull が失敗する。Layer データは S3 に格納されているため s3 Endpoint が必須。


## 7.3 Security Group 設計

| SG 名 | 適用対象 | インバウンド | アウトバウンド |
| --- | --- | --- | --- |
| endpoint-sg | VPC Endpoint | 443/tcp from VPC CIDR | なし |
| cluster-sg | EKS クラスター | node-sg から 443/tcp | 全許可 |
| node-sg | EKS ノード | cluster-sg から全ポート | 全許可（VPC 内） |
| bastion-sg | 踏み台 EC2 | なし（SSM のみ） | endpoint-sg への 443 |
| build-sg | CodeBuild | なし | endpoint-sg への 443 |


## 7.4 通信経路サマリ

| 送信元 | 送信先 | 経路 | ポート |
| --- | --- | --- | --- |
| EKS ノード | ECR | ecr.dkr + s3 VPC Endpoint | 443 |
| CodeBuild | ECR | ecr.dkr + s3 VPC Endpoint | 443 |
| Pod | STS | sts VPC Endpoint | 443 |
| 踏み台 EC2 | EKS API | eks VPC Endpoint | 443 |
| 踏み台 EC2 | SSM | ssm / ssmmessages VPC Endpoint | 443 |
| Karpenter | EC2 API | ec2 / autoscaling VPC Endpoint | 443 |
| 全リソース | CloudWatch Logs | logs VPC Endpoint | 443 |


# 8. EKS 設計


## 8.1 クラスター設計方針

| 設定項目 | 値 | 理由 |
| --- | --- | --- |
| Kubernetes バージョン | 1.31 | LTS 相当の最新安定版。年 1 回のバージョンアップ計画を立てる |
| API サーバーアクセス | Private Only | ADR-006：インターネットからの到達を構造的に排除 |
| 認証モード | API モード | ConfigMap（aws-auth）管理を排除。アクセスエントリ API で一元管理 |
| Pod Identity | EKS アドオン | ADR-004：IRSA を使わない |
| EKS アドオン | vpc-cni / coredns / kube-proxy / pod-identity-agent | 3.1 方針：マネージドアドオンで運用コスト削減 |


## 8.2 ノード設計


### System Managed Node Group

システム Pod（ArgoCD、Karpenter）専用ノード。Taint で一般 Pod の混入を防ぐ。

| 設定項目 | 値 |
| --- | --- |
| インスタンスタイプ | m5.large（2vCPU / 8GB） |
| 台数 | 常時 2 台（Min:2 / Max:4、2AZ に分散） |
| Taint | `dedicated=system:NoSchedule` |
| Label | `role=system` |
| IMDSv2 | 必須（HttpTokens: required） |


> 💡 **なぜ**　System Node Group を 2AZ に常時 2 台維持することで、片方の AZ が障害を起こしても ArgoCD と Karpenter が稼働し続ける。これが欠けると管理機能が全停止する。


### Karpenter Workload Node

アプリケーション Pod 専用ノード。負荷に応じて動的にプロビジョニング・削除される。

| 設定項目 | 値 |
| --- | --- |
| インスタンスタイプ | m5 系・c5 系（NodePool で定義） |
| 容量タイプ | On-Demand |
| AMI | Amazon Linux 2023（`al2023@latest`） |
| Consolidation | WhenEmptyOrUnderutilized（1 分後） |
| IMDSv2 | 必須（httpTokens: required） |


## 8.3 Pod 配置制御

システム Pod は以下の設定でSystemノードに固定する。

| 設定 | 適用先 | 値 |
| --- | --- | --- |
| Taint | System Node Group | `dedicated=system:NoSchedule` |
| Toleration | ArgoCD / Karpenter Pod | `dedicated=system:NoSchedule` を許容 |
| NodeSelector | ArgoCD / Karpenter Pod | `role: system` |


# 9. CI/CD 設計


## 9.1 CI 設計（CodeBuild）


### パイプライン責務

| フェーズ | 処理内容 |
| --- | --- |
| pre_build | IMAGE_TAG 生成（commit SHA 8 桁）、ECR ログイン |
| build | docker build、docker push（ECR へ） |
| post_build | GitOps リポジトリの image tag を kustomize で更新し git push |


### プロジェクト設定方針

| 設定項目 | 値 | 理由 |
| --- | --- | --- |
| ビルド環境 | Amazon Linux 2023 managed image | 標準環境で再現性確保 |
| 特権モード | 有効 | docker build に必須 |
| VPC 設定 | EKS と同じ Private Subnet | ECR・STS へ VPC Endpoint 経由アクセス |
| ログ | CloudWatch Logs（logs VPC Endpoint 経由） | インターネット通信なし |
| IAM 権限 | ECR Push / GitOps Repo Push / Logs | 最小権限（CodeBuild サービスロール） |


## 9.2 CD 設計（ArgoCD）


### インストール方針

Helm で System Node Group 上にインストール。Pod には Taint Toleration と NodeSelector を付与して System Node Group に固定する。


### 設定方針

| 設定項目 | 値 | 理由 |
| --- | --- | --- |
| Service タイプ | ClusterIP | 外部 LB 不使用。kubectl port-forward または内部 ALB でアクセス |
| ポーリング間隔 | 180 秒（3 分） | デフォルト値。Push-based に変更する場合は Webhook を設定 |
| TLS | server.insecure: true | TLS 終端を上位レイヤーで行う場合に設定 |


## 9.3 Git リポジトリ構成

```
gitops-repo/
├── base/
│   ├── deployment.yaml
│   ├── service.yaml
│   └── kustomization.yaml
└── overlays/
    ├── dev/
    │   └── kustomization.yaml   ← CI が image tag を更新
    └── prod/
        └── kustomization.yaml   ← CI が image tag を更新
```

> 💡 **なぜ**　アプリコードと Kubernetes マニフェストを別リポジトリで管理することで、インフラ変更とアプリ変更の履歴が分離される。また ArgoCD がソースリポジトリに直接アクセスする必要がなくなる。


# 10. 認証・認可設計


## 10.1 Pod Identity 設計原則

**1 Pod = 1 ServiceAccount = 1 IAM Role** の対応関係を維持する。

> 💡 **なぜ**　この原則により、どの Pod がどの AWS サービスにアクセスできるかが設計書から一意に追跡できる。IAM ロールを共有すると、一方の権限が漏れた際に他方にも影響する。


## 10.2 Pod Identity 対応表

| コンポーネント | Namespace | ServiceAccount | 必要な IAM 権限 |
| --- | --- | --- | --- |
| Karpenter | karpenter | karpenter | EC2 起動/終了、EKS NodeClaim 管理 |
| ArgoCD Server | argocd | argocd-server | 最小限（Git アクセスは SSH Key 別管理） |
| Application | `<app>` | `<app>-sa` | アプリ固有（例: Secrets Manager 読み取り等） |


## 10.3 管理者 EKS アクセス

SSO ユーザーに EKS Access Entry を作成して kubectl アクセス権を付与する。ConfigMap（`aws-auth`）は使用しない（8.1 設計方針）。


## 10.4 IAM 権限マトリクス

| コンポーネント | ECR Push | ECR Pull | EC2 操作 | EKS 操作 | Logs 書き込み |
| --- | --- | --- | --- | --- | --- |
| CodeBuild | ✅ | ❌ | ❌ | ❌ | ✅ |
| EKS ノード（NodeRole） | ❌ | ✅ | ❌ | ❌ | ✅ |
| Karpenter Pod | ❌ | ❌ | ✅ | ✅ | ✅ |
| Application Pod | ❌ | ❌ | ❌ | ❌ | ✅（アプリログ） |
| 踏み台 EC2 | ❌ | ❌ | ❌ | ✅（kubectl） | ❌ |


# 11. ECR 設計

| 設定項目 | 値 | 理由 |
| --- | --- | --- |
| リポジトリタイプ | Private | 外部公開不要 |
| ScanOnPush | 有効 | push 時に CVE を自動検出。高危険度は CI を失敗させることも検討 |
| 暗号化 | KMS | デフォルト AES256 より強固。KMS キーで暗号化証跡も管理できる |
| ライフサイクルポリシー | 最新 20 イメージを保持、古いものを削除 | ストレージコスト削減 |
| imagePullSecrets | 不使用 | ノードの IAM ロール（ECR ReadOnly）で Pull する |


# 12. 監視設計

CloudWatch を監視基盤として採用する（3.1 Managed First 方針）。


## 12.1 メトリクス収集

| 収集対象 | 手段 | 主要メトリクス |
| --- | --- | --- |
| Node | CloudWatch Container Insights | CPU / Memory / Disk 使用率 |
| Pod | CloudWatch Container Insights | CPU / Memory 使用率、再起動回数 |
| Namespace | CloudWatch Container Insights | リソース集計 |
| EKS クラスター | EKS マネージドメトリクス | API サーバー応答時間、etcd 健全性 |
| Karpenter | Karpenter メトリクス（CloudWatch 転送） | Node 起動時間、Disruption 回数 |


## 12.2 ログ収集

| ログ種別 | 収集先 | 保持期間 |
| --- | --- | --- |
| コンテナログ（stdout/stderr） | CloudWatch Logs（/aws/containerinsights/） | 90 日 |
| EKS コントロールプレーンログ | CloudWatch Logs（/aws/eks/<cluster>/） | 90 日 |
| CodeBuild ビルドログ | CloudWatch Logs（/codebuild/<app>） | 30 日 |
| VPC フローログ | CloudWatch Logs（/aws/vpc/） | 365 日（監査要件） |
| CloudTrail | S3 + CloudWatch Logs | 365 日（監査要件） |


## 12.3 アラート設計

| アラート名 | 条件 | 重要度 | 通知先 |
| --- | --- | --- | --- |
| NodeNotReady | ノード Ready = false が 5 分継続 | Critical | SNS → 担当者 |
| PodCrashLoopBackOff | restartCount > 5 / 10 分 | Warning | SNS → 担当者 |
| NodeCPUHigh | Node CPU > 80% が 5 分継続 | Warning | SNS |
| NodeMemoryHigh | Node Memory > 80% が 5 分継続 | Warning | SNS |
| KarpenterNodeProvisionFail | NodeClaim が 3 分以内に Ready にならない | Critical | SNS → 担当者 |
| ArgoCDSyncFailed | ArgoCD Application が Degraded 状態 | Warning | SNS → 担当者 |
| CodeBuildFailed | ビルドステータス = FAILED | Warning | SNS → 担当者 |


## 12.4 Container Insights 有効化

EKS クラスター作成後、踏み台 EC2 から以下を実行して Container Insights を有効化する。

（CloudFormation カスタムリソースまたは手動で適用。CFn サンプルは Appendix A 参照。）


# 13. 運用設計


## 13.1 管理者アクセス

```
Windows PC
 └─▶ aws sso login
       └─▶ aws eks update-kubeconfig
             └─▶ SSM Session Manager
                   └─▶ 踏み台 EC2
                         └─▶ kubectl
```

踏み台 EC2 は SSM Session Manager でのみアクセスする。SSH ポートは開放しない（bastion-sg にインバウンドなし）。


## 13.2 Kubernetes バージョンアップ

| 手順 | 内容 |
| --- | --- |
| 1. 事前確認 | EKS リリースノートで非推奨 API を確認。アプリマニフェストに影響がないかチェック |
| 2. アドオン更新 | vpc-cni / coredns / kube-proxy を新バージョンに合わせて更新（CFn で管理） |
| 3. クラスター更新 | CFn の Version パラメータを変更してスタック更新 |
| 4. ノード更新 | Managed Node Group のローリング更新を実行 |
| 5. 確認 | kubectl get nodes / kubectl get pods -A で異常がないことを確認 |


## 13.3 障害対応フロー

| 障害ケース | 初動対応 |
| --- | --- |
| Pod が CrashLoopBackOff | `kubectl describe pod` でイベント確認 → ログ調査 |
| Karpenter がノードを起動しない | Karpenter Pod のログ確認 → IAM 権限 / EC2 クォータ確認 |
| ArgoCD が Sync しない | ArgoCD UI で差分確認 → Git リポジトリ疎通確認 |
| ECR pull 失敗 | VPC Endpoint（ecr.dkr, s3）の疎通確認 → Security Group 確認 |
| EKS API に到達できない | 踏み台 EC2 → eks VPC Endpoint の 443 疎通確認 |


## 13.4 バックアップ

| 対象 | 方式 | 頻度 |
| --- | --- | --- |
| CloudFormation テンプレート | Git 管理（真実源） | 変更の都度 |
| Kubernetes マニフェスト | Git 管理（GitOps リポジトリ） | 変更の都度 |
| ECR イメージ | ライフサイクルポリシーで最新 20 件保持 | 常時 |
| CloudWatch Logs | S3 エクスポート（監査ログのみ） | 月次 |


# 14. 非機能要件

| 区分 | 要件 | 実現方法 |
| --- | --- | --- |
| 可用性 | System Pod は AZ 障害に耐性を持つ | System Node Group を 2AZ に分散（常時 2 台） |
| セキュリティ | インターネット経由通信なし | NAT GW 不使用。全通信を VPC Endpoint 経由（ADR-005） |
| セキュリティ | Static AccessKey 不使用 | Pod Identity / CodeBuild Service Role（ADR-004） |
| セキュリティ | IMDSv2 必須 | 全 EC2 / EKS ノードで HttpTokens: required |
| セキュリティ | EKS API は Private のみ | EndpointPublicAccess: false（ADR-006） |
| 監査 | リソース変更履歴の保持 | CloudFormation / Git / CloudTrail |
| コスト | ワークロードノードの最適化 | Karpenter consolidation（未使用ノードを自動削除） |
| 再現性 | 環境の再構築が可能 | CloudFormation 全リソース管理。手動作成禁止（3.6 方針） |


# 15. 受入条件

以下が全て成功することをもって本基盤の構築完了とする。


| No | 確認項目 | 確認方法 | 合格基準 |
| --- | --- | --- | --- |
| 1 | EKS クラスター作成 | `kubectl get nodes` | System Node 2 台以上が Ready |
| 2 | Pod Identity 動作 | テスト Pod から STS コール | 一時クレデンシャル取得成功 |
| 3 | ECR イメージ Pull | テスト Pod 起動 | ECR イメージが VPC Endpoint 経由で Pull される |
| 4 | CodeBuild CI | Git Push → ビルドトリガー | ECR Push と GitOps Repo 更新が成功 |
| 5 | ArgoCD CD | GitOps Repo 更新 → Sync | EKS 上の Pod が新イメージで再起動 |
| 6 | Karpenter スケールアウト | Pending Pod を発生させる | 60 秒以内にノードが Ready になる |
| 7 | Karpenter スケールイン | 負荷を下げて 5 分待つ | 不要ノードが終了し EC2 が削除される |
| 8 | 踏み台アクセス | SSM Session Manager で接続 | SSH 不使用で kubectl 実行成功 |
| 9 | インターネット遮断 | 踏み台から `curl ifconfig.me` | タイムアウト（外部到達不可） |
| 10 | 監視動作 | CloudWatch Container Insights で確認 | Node / Pod メトリクスが収集されている |


# 16. 実装設計

本章は実装者向けである。レビューアは 1〜15 章で設計判断を確認すること。


## 16.1 CloudFormation スタック構成

| No | スタック名 | 主なリソース | 依存 |
| --- | --- | --- | --- |
| 01 | network | VPC / Subnet / RouteTable / VPC Endpoint / SG | なし |
| 02 | iam-base | Cluster Role / Node Role / CodeBuild Role | なし |
| 03 | ecr | ECR リポジトリ | なし |
| 04 | eks-cluster | EKS Cluster / アドオン | 01, 02 |
| 05 | managed-ng | System Managed Node Group | 04 |
| 06 | karpenter-iam | Karpenter Controller Role / Node Instance Profile | 02 |
| 07 | bastion | 踏み台 EC2 / Instance Profile | 01, 02 |
| 08 | codebuild | CodeBuild Project | 01, 02, 03 |
| 09 | pod-identity | Pod Identity Associations | 04, 02 |
| 10 | observability | CloudWatch Log Groups / Alarms / Container Insights | 04 |


## 16.2 デプロイ手順（PowerShell）

```powershell
# Windows PowerShell / SSO 認証済み前提
$Region  = "ap-northeast-1"
$Prefix  = "myapp"

# スタックを番号順にデプロイ
# 例: 01-network
aws cloudformation deploy `
  --template-file .\cfn\01-network.yaml `
  --stack-name "$Prefix-network" `
  --parameter-overrides VpcCidr=10.0.0.0/16 `
  --region $Region

# スタック出力を取得して後続スタックのパラメータに使う
$out = aws cloudformation describe-stacks `
  --stack-name "$Prefix-network" `
  --query "Stacks[0].Outputs" `
  --output json | ConvertFrom-Json
$VpcId = ($out | Where-Object OutputKey -eq VpcId).OutputValue

# ── 05-managed-ng まで完了後 ──
# 踏み台 EC2 で kubeconfig を設定
# aws eks update-kubeconfig --name <cluster> --region $Region

# ── Helm インストール（踏み台 EC2 上で実行）──
# helm upgrade --install karpenter oci://public.ecr.aws/karpenter/karpenter ...
# helm upgrade --install argocd argo/argo-cd ...
```


## 16.3 CloudFormation 管理対象サマリ

| リソース種別 | 管理方法 |
| --- | --- |
| VPC / Subnet / VPC Endpoint / SG | CFn スタック 01 |
| IAM Role（Cluster / Node / CodeBuild / Karpenter） | CFn スタック 02, 06 |
| ECR リポジトリ | CFn スタック 03 |
| EKS Cluster / アドオン | CFn スタック 04 |
| Managed Node Group | CFn スタック 05 |
| 踏み台 EC2 | CFn スタック 07 |
| CodeBuild Project | CFn スタック 08 |
| Pod Identity Association | CFn スタック 09 |
| CloudWatch Log Groups / Alarms | CFn スタック 10 |
| Karpenter NodePool / EC2NodeClass | Kubernetes マニフェスト（GitOps） |
| ArgoCD Application | Kubernetes マニフェスト（GitOps） |


## 16.4 Security Group 通信表

| 送信元 SG | 送信先 SG / リソース | ポート | 用途 |
| --- | --- | --- | --- |
| node-sg | endpoint-sg | 443 | ECR / STS / Logs VPC Endpoint |
| node-sg | cluster-sg | 443 | EKS API サーバーへの通信 |
| cluster-sg | node-sg | 全 | EKS コントロールプレーン → ノード |
| bastion-sg | endpoint-sg | 443 | SSM / EKS API VPC Endpoint |
| build-sg | endpoint-sg | 443 | ECR / STS / Logs VPC Endpoint |


## 16.5 Pod Identity 設定手順

以下の順序で設定する。詳細な CFn コードは Appendix A 参照。

- 1. CFn スタック 02 で IAM Role を作成（trust policy: `pods.eks.amazonaws.com`）
- 2. CFn スタック 09 で `AWS::EKS::PodIdentityAssociation` を作成
- 3. Kubernetes 上で ServiceAccount を作成（Helm values または マニフェストで管理）
- 4. Pod の spec.serviceAccountName に ServiceAccount を指定

# 17. 未定義事項

以下はコード実装前に確定が必要な事項である。確定次第、本書を更新し ADR に追記すること。


| No | 事項 | 影響章 | 期限 |
| --- | --- | --- | --- |
| 1 | Git リポジトリサービスの選定（CodeCommit / GitHub / GitLab 等） | 9章, ADR追加 | 実装前 |
| 2 | ArgoCD UI へのアクセス方法（kubectl port-forward / 内部 ALB） | 9.2章 | 実装前 |
| 3 | Secrets 管理方式（Secrets Manager + External Secrets Operator 等） | 新章追加 | 実装前 |
| 4 | Karpenter NodePool のインスタンスタイプ制約とコスト上限 | 16章 | 実装前 |
| 5 | ArgoCD SSO 設定（SAML / OIDC） | 10章追加 | Phase2 |
| 6 | アプリ用 Namespace・ResourceQuota 設計 | 6.2章更新 | Phase2 |
| 7 | PodDisruptionBudget 設計（スケールイン時の可用性保証） | 8章追加 | Phase2 |


---


# Appendix A. CFn サンプル抜粋

本体設計書（1〜16 章）から切り出した実装参考コード。設計判断の変更は本体を更新し、本 Appendix はそれに追従させること。


## A.1 VPC Endpoint（ecr.api / ecr.dkr / s3）

```yaml
Resources:
  VpcEndpointEcrApi:
    Type: AWS::EC2::VPCEndpoint
    Properties:
      VpcId: !Ref VpcId
      ServiceName: !Sub com.amazonaws.${AWS::Region}.ecr.api
      VpcEndpointType: Interface
      SubnetIds: !Ref PrivateSubnetIds
      SecurityGroupIds: [!Ref EndpointSG]
      PrivateDnsEnabled: true   # 必須

  VpcEndpointEcrDkr:
    Type: AWS::EC2::VPCEndpoint
    Properties:
      VpcId: !Ref VpcId
      ServiceName: !Sub com.amazonaws.${AWS::Region}.ecr.dkr
      VpcEndpointType: Interface
      SubnetIds: !Ref PrivateSubnetIds
      SecurityGroupIds: [!Ref EndpointSG]
      PrivateDnsEnabled: true

  VpcEndpointS3:               # ECR Layer 取得に必須
    Type: AWS::EC2::VPCEndpoint
    Properties:
      VpcId: !Ref VpcId
      ServiceName: !Sub com.amazonaws.${AWS::Region}.s3
      VpcEndpointType: Gateway
      RouteTableIds: !Ref PrivateRouteTableIds
```


## A.2 EKS Cluster / Pod Identity Addon / System Node Group

```yaml
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
        EndpointPublicAccess: false     # ADR-006
      AccessConfig:
        AuthenticationMode: API         # ConfigMap 不使用
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


## A.3 Pod Identity Association（Karpenter）

```yaml
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

  KarpenterAssociation:
    Type: AWS::EKS::PodIdentityAssociation
    Properties:
      ClusterName: !Ref ClusterName
      Namespace: karpenter
      ServiceAccount: karpenter
      RoleArn: !GetAtt KarpenterControllerRole.Arn
```


---


# Appendix B. buildspec.yaml

```yaml
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
```


---


# Appendix C. Helm values 骨格


## C.1 argocd-values.yaml

```yaml
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
    type: ClusterIP
  extraArgs:
    - --insecure
configs:
  params:
    server.insecure: true
  cm:
    timeout.reconciliation: 180s
```


## C.2 karpenter-values.yaml（主要項目）

```yaml
settings:
  clusterName: <cluster-name>
  interruptionQueue: <sqs-queue-name>   # スポット割り込み通知用（On-Demand のみなら不要）
tolerations:
  - key: dedicated
    value: system
    operator: Equal
    effect: NoSchedule
nodeSelector:
  role: system
```


---


# Appendix D. Kubernetes マニフェスト骨格


## D.1 Karpenter NodePool / EC2NodeClass

```yaml
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
    httpTokens: required    # IMDSv2 強制
```


## D.2 ArgoCD Application

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: <app-name>
  namespace: argocd
spec:
  project: default
  source:
    repoURL: <gitops-repo-url>
    targetRevision: main
    path: overlays/prod
  destination:
    server: https://kubernetes.default.svc
    namespace: <app-name>
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```
