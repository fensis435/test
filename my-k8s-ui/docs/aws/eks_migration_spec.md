# EKS移行仕様書

| 項目 | 内容 |
|------|------|
| 文書バージョン | 1.0.0 |
| 作成日 | 2025-XX-XX |
| 作成者 | XXXX |
| ステータス | Draft |

---

## 目次

1. [概要・目的](#1-概要目的)
2. [前提条件・スコープ](#2-前提条件スコープ)
3. [現状オンプレ構成（As-Is）](#3-現状オンプレ構成as-is)
4. [EKS構成設計（To-Be）](#4-eks構成設計to-be)
5. [CFnスタック設計](#5-cfnスタック設計)
6. [K8sマニフェスト変更一覧](#6-k8sマニフェスト変更一覧)
7. [スケーリング設計](#7-スケーリング設計)
8. [デプロイ手順](#8-デプロイ手順)
9. [テスト・受け入れ基準](#9-テスト受け入れ基準)
10. [非機能要件](#10-非機能要件)

---

## 1. 概要・目的

### 1-1. 背景

現在、〇〇サービスはオンプレミスのKubernetesクラスタ上で稼働している。
クラウド化によるスケーラビリティの確保・インフラ運用負荷の軽減・可用性向上を目的として、AWS EKSへ移行する。

### 1-2. 目的

| 目的 | 内容 |
|------|------|
| スケーラビリティ | 負荷変動に対して自動でPod・ノードをスケールさせ、手動対応を不要にする |
| 可用性向上 | マルチAZ構成によりAZ障害を許容する |
| 運用負荷軽減 | マネージドサービスの活用でK8sコントロールプレーンの運用を不要にする |
| コスト最適化 | スポットインスタンスの活用・オートスケールにより無駄なリソースを削減する |

### 1-3. 移行方針

- **移行種別**: リフト＆シフト（アプリケーションコードの変更なし）
- **データマイグレーション**: 不要（新規構築として扱う）
- **IaC**: AWS CloudFormation（CFn）を使用する
- **本仕様書**: これ一つで実装まで移行できる粒度で記述する

---

## 2. 前提条件・スコープ

### 2-1. 前提条件

- AWSアカウントは作成済みであること
- 移行対象サービスのコンテナイメージはECRに移行済みであること（または移行手順を別途実施すること）
- 作業者はAWS CLIおよびkubectlの操作が可能であること
- AWSリージョン: **ap-northeast-1（東京）**
- 本番環境と同一構成でステージング環境も構築する（本仕様書はステージングも兼ねる）

### 2-2. スコープ

**対象（スコープ内）**

- 〇〇サービスのEKSへの移行
- 関連するAWSインフラリソース（VPC、IAM、ECR等）の構築
- 監視・ロギング設定
- スケーリング設定

**対象外（スコープ外）**

- アプリケーションコードの変更
- データマイグレーション
- オンプレ環境の廃止作業
- CI/CDパイプラインの変更

### 2-3. 命名規則

全リソースは以下の規則に従って命名する。

```
{サービス名}-{環境}-{リソース種別}
例: myapp-prod-eks-cluster
    myapp-stg-vpc
```

| 変数 | 値 |
|------|----|
| `SERVICE_NAME` | myapp |
| `ENV` | prod / stg |
| `AWS_REGION` | ap-northeast-1 |
| `AWS_ACCOUNT_ID` | XXXXXXXXXXXX |

---

## 3. 現状オンプレ構成（As-Is）

### 3-1. クラスタ構成

| 項目 | 値 |
|------|----|
| Kubernetesバージョン | 1.28 |
| ノード数 | 3 |
| ノードスペック | 8vCPU / 32GB RAM |
| CNI | Calico |
| CRI | containerd |
| Ingressコントローラ | Nginx Ingress Controller |

### 3-2. デプロイ構成

| 項目 | 値 |
|------|----|
| ワークロード種別 | Deployment |
| レプリカ数 | 2 |
| コンテナイメージ | {既存レジストリ}/myapp:latest |
| Namespace | myapp |

### 3-3. リソース定義（現状）

| | CPU | Memory |
|-|-----|--------|
| requests | 250m | 256Mi |
| limits | 500m | 512Mi |

### 3-4. ネットワーク

| 項目 | 値 |
|------|----|
| Service種別 | ClusterIP |
| Ingressホスト | myapp.internal.example.com |
| 内部DNS | CoreDNS |

### 3-5. ストレージ

| 項目 | 値 |
|------|----|
| PV利用 | なし（ステートレス構成） |
| 外部DB | PostgreSQL（オンプレ別サーバ） |

### 3-6. 設定・シークレット管理

| 項目 | 値 |
|------|----|
| ConfigMap | あり（アプリ設定） |
| Secret | あり（DB接続情報、APIキー等） |
| 外部連携 | なし（K8s Secretで完結） |

### 3-7. 依存サービス

| サービス | 種別 | 接続先 |
|---------|------|--------|
| PostgreSQL | RDB | 192.168.x.x:5432 |
| Redis | Cache | 192.168.x.x:6379 |

### 3-8. 認証・認可

| 項目 | 値 |
|------|----|
| RBAC | あり |
| ServiceAccount | myapp-sa |

### 3-9. 監視・ロギング

| 項目 | 値 |
|------|----|
| メトリクス | Prometheus + Grafana |
| ロギング | Fluentd → Elasticsearch |
| アラート | Alertmanager |

---

## 4. EKS構成設計（To-Be）

### 4-1. インフラ構成

#### EKSクラスタ

| 項目 | 値 |
|------|----|
| クラスタ名 | myapp-prod-eks-cluster |
| Kubernetesバージョン | 1.30 |
| エンドポイントアクセス | パブリック + プライベート |
| ログ記録 | api, audit, authenticator, controllerManager, scheduler |

#### ノード構成

| 項目 | 値 |
|------|----|
| ノード管理 | Karpenter（マネージドノードグループは使用しない） |
| 初期ノード数 | 2（Karpenterが動作するための最小構成） |
| 初期ノードインスタンスタイプ | m5.xlarge（Karpenter自身が動く専用ノードグループ） |

#### AWSアドオン

| アドオン | バージョン | 用途 |
|---------|-----------|------|
| vpc-cni | v1.18.x-eksbuild.x | Pod間ネットワーク |
| coredns | v1.11.x-eksbuild.x | 内部DNS |
| kube-proxy | v1.30.x-eksbuild.x | ネットワークルール |
| aws-ebs-csi-driver | v1.31.x-eksbuild.x | EBS永続ボリューム |

### 4-2. ネットワーク設計

#### VPC構成

| 項目 | 値 |
|------|----|
| VPC CIDR | 10.0.0.0/16 |
| AZ | ap-northeast-1a, ap-northeast-1c, ap-northeast-1d |

#### サブネット構成

| サブネット種別 | AZ | CIDR | 用途 |
|--------------|-----|------|------|
| パブリック | 1a | 10.0.0.0/24 | ALB、NAT Gateway |
| パブリック | 1c | 10.0.1.0/24 | ALB、NAT Gateway |
| パブリック | 1d | 10.0.2.0/24 | ALB、NAT Gateway |
| プライベート | 1a | 10.0.10.0/24 | EKSノード、Pod |
| プライベート | 1c | 10.0.11.0/24 | EKSノード、Pod |
| プライベート | 1d | 10.0.12.0/24 | EKSノード、Pod |

#### Ingressコントローラ

オンプレのNginx IngressからAWS Load Balancer Controller（ALB）に移行する。

| 項目 | 値 |
|------|----|
| コントローラ | AWS Load Balancer Controller v2.8.x |
| ALB種別 | internet-facing |
| リスナー | HTTPS:443（ACM証明書使用） |
| ターゲット | IP mode |
| インストール方法 | Helmチャート（kubectlで適用） |

#### セキュリティグループ設計

| SG名 | 対象 | インバウンド | アウトバウンド |
|------|------|------------|--------------|
| myapp-prod-alb-sg | ALB | 0.0.0.0/0:443 | ノードSG:任意 |
| myapp-prod-node-sg | EKSノード | ALB SG:任意、ノードSG:任意 | 0.0.0.0/0:任意 |
| myapp-prod-cluster-sg | EKSコントロールプレーン | ノードSG:任意 | ノードSG:任意 |

### 4-3. ストレージ設計

本サービスはステートレス構成のためPVは不要。
将来的な利用に備えてEBS CSI DriverをEKSアドオンとして導入する。

| 項目 | 値 |
|------|----|
| StorageClass | gp3（EBS CSI Driver使用） |
| 現時点でのPV利用 | なし |

### 4-4. IAM・認証設計

#### IRSA（IAM Roles for Service Accounts）

PodがAWSリソースにアクセスする際はIRSAを使用する。EC2インスタンスプロファイルには頼らない。

| ServiceAccount | IAMロール名 | 権限 |
|---------------|------------|------|
| myapp-sa | myapp-prod-app-role | Secrets Manager読み取り |
| aws-load-balancer-controller | myapp-prod-alb-controller-role | ALB操作権限 |
| karpenter | myapp-prod-karpenter-role | EC2操作権限 |

#### OIDCプロバイダー

EKSクラスタのOIDCプロバイダーをCFnで作成し、IRSAの信頼ポリシーと紐付ける。

#### クラスタアクセス（aws-auth）

| 対象 | 権限 |
|------|------|
| 管理者IAMロール | system:masters |
| 開発者IAMロール | system:masters（ステージングのみ） / viewのみ（本番） |
| KarpenterノードIAMロール | system:bootstrappers, system:nodes |

### 4-5. シークレット管理

オンプレのK8s Secretに代わり、AWS Secrets Managerと**External Secrets Operator（ESO）**を使用する。

| 項目 | 値 |
|------|----|
| シークレット格納先 | AWS Secrets Manager |
| K8sとの連携 | External Secrets Operator v0.9.x |
| 同期間隔 | 1時間 |
| インストール方法 | Helmチャート（kubectlで適用） |

#### シークレット一覧

| シークレット名（Secrets Manager） | 内容 | 参照するPod |
|---------------------------------|------|------------|
| myapp/prod/db | DB接続情報（host, port, user, password） | myapp |
| myapp/prod/redis | Redis接続情報 | myapp |
| myapp/prod/api-keys | 外部APIキー | myapp |

#### ExternalSecret定義例

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: myapp-secret
  namespace: myapp
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: aws-secrets-manager
    kind: ClusterSecretStore
  target:
    name: myapp-secret
    creationPolicy: Owner
  data:
    - secretKey: DB_PASSWORD
      remoteRef:
        key: myapp/prod/db
        property: password
```

### 4-6. 監視・ロギング

#### メトリクス

| 項目 | 値 |
|------|----|
| 方式 | CloudWatch Container Insights |
| エージェント | CloudWatch Agent（DaemonSet） |
| カスタムメトリクス | アプリケーション固有のメトリクスはCloudWatch EMFで送信 |

#### ロギング

| 対象 | 送信先 | 方式 |
|------|--------|------|
| アプリログ | CloudWatch Logs | Fluentd（DaemonSet） |
| EKSコントロールプレーンログ | CloudWatch Logs | EKSの組み込み機能 |
| ALBアクセスログ | S3 | ALBの組み込み機能 |

#### ロググループ設計

| ロググループ名 | 保持期間 |
|--------------|---------|
| /aws/eks/myapp-prod-eks-cluster/cluster | 90日 |
| /myapp/prod/application | 30日 |
| /myapp/prod/alb-access | 30日 |

#### アラート設計

アラームリソースはすべてCFnで管理する（`AWS::CloudWatch::Alarm`）。

| アラーム名 | 条件 | 通知先 |
|-----------|------|-------|
| myapp-prod-cpu-high | Pod平均CPU > 80%が5分継続 | SNS（運用チームSlack） |
| myapp-prod-memory-high | Pod平均Memory > 85%が5分継続 | SNS（運用チームSlack） |
| myapp-prod-pod-pending | PendingのPodが10分以上 | SNS（運用チームSlack） |
| myapp-prod-hpa-maxreplicas | HPAがmaxReplicasに5分以上 | SNS（運用チームSlack） |
| myapp-prod-node-limit | Karpenterのノードが上限到達 | SNS（運用チームSlack） |
| myapp-prod-5xx-rate | ALB 5xxエラー率 > 1%が3分継続 | SNS（運用チームSlack） |

---

## 5. CFnスタック設計

### 5-1. スタック分割方針

スタックは**3層**に分割する。各層は独立してデプロイ可能とし、上位層は`Fn::ImportValue`で下位層のOutputsを参照する。

```
[Layer 1] network-stack          ← VPC、サブネット、SG、IGW、NAT
      ↓ ImportValue
[Layer 2] eks-stack              ← EKSクラスタ、ノードグループ、IAMロール、OIDC
      ↓ ImportValue
[Layer 3] app-stack              ← ECR、Secrets Manager、CloudWatch、SNS、S3（ログ用）
```

### 5-2. 各スタックのリソース一覧

#### Layer 1: network-stack

| 論理ID | CFnリソースタイプ | 概要 |
|--------|-----------------|------|
| VPC | AWS::EC2::VPC | 10.0.0.0/16 |
| PublicSubnet1a | AWS::EC2::Subnet | パブリック/1a |
| PublicSubnet1c | AWS::EC2::Subnet | パブリック/1c |
| PublicSubnet1d | AWS::EC2::Subnet | パブリック/1d |
| PrivateSubnet1a | AWS::EC2::Subnet | プライベート/1a |
| PrivateSubnet1c | AWS::EC2::Subnet | プライベート/1c |
| PrivateSubnet1d | AWS::EC2::Subnet | プライベート/1d |
| InternetGateway | AWS::EC2::InternetGateway | IGW |
| VPCGatewayAttachment | AWS::EC2::VPCGatewayAttachment | IGW-VPC紐付け |
| NatGateway1a | AWS::EC2::NatGateway | NAT/1a |
| NatGateway1c | AWS::EC2::NatGateway | NAT/1c |
| EIPForNat1a | AWS::EC2::EIP | NATのEIP |
| EIPForNat1c | AWS::EC2::EIP | NATのEIP |
| PublicRouteTable | AWS::EC2::RouteTable | パブリック用 |
| PrivateRouteTable1a | AWS::EC2::RouteTable | プライベート/1a用 |
| PrivateRouteTable1c | AWS::EC2::RouteTable | プライベート/1c用 |
| ALBSecurityGroup | AWS::EC2::SecurityGroup | ALB用SG |
| NodeSecurityGroup | AWS::EC2::SecurityGroup | ノード用SG |
| ClusterSecurityGroup | AWS::EC2::SecurityGroup | コントロールプレーン用SG |

**Outputs（Layer 2へ渡す値）**

| Export名 | 値 |
|---------|-----|
| myapp-prod-vpc-id | VPCのID |
| myapp-prod-private-subnet-1a | プライベートサブネット1aのID |
| myapp-prod-private-subnet-1c | プライベートサブネット1cのID |
| myapp-prod-private-subnet-1d | プライベートサブネット1dのID |
| myapp-prod-public-subnet-1a | パブリックサブネット1aのID |
| myapp-prod-alb-sg-id | ALB SG ID |
| myapp-prod-node-sg-id | ノード SG ID |
| myapp-prod-cluster-sg-id | クラスタ SG ID |

#### Layer 2: eks-stack

| 論理ID | CFnリソースタイプ | 概要 |
|--------|-----------------|------|
| EKSClusterRole | AWS::IAM::Role | クラスタIAMロール |
| EKSCluster | AWS::EKS::Cluster | EKSクラスタ本体 |
| OIDCProvider | AWS::IAM::OIDCProvider | IRSAのためのOIDC |
| KarpenterNodeRole | AWS::IAM::Role | Karpenterが起動するノードのロール |
| KarpenterControllerRole | AWS::IAM::Role | KarpenterコントローラのIRSAロール |
| ALBControllerRole | AWS::IAM::Role | ALBコントローラのIRSAロール |
| AppServiceAccountRole | AWS::IAM::Role | myappサービスアカウントのIRSAロール |
| InitialNodeGroup | AWS::EKS::Nodegroup | Karpenter用初期ノードグループ |
| VPCCNIAddon | AWS::EKS::Addon | VPC CNIアドオン |
| CoreDNSAddon | AWS::EKS::Addon | CoreDNSアドオン |
| KubeProxyAddon | AWS::EKS::Addon | kube-proxyアドオン |
| EBSCSIDriverAddon | AWS::EKS::Addon | EBS CSI Driverアドオン |
| KarpenterAddon | AWS::EKS::Addon | Karpenterアドオン |

**Outputs（Layer 3へ渡す値）**

| Export名 | 値 |
|---------|-----|
| myapp-prod-cluster-name | EKSクラスタ名 |
| myapp-prod-cluster-arn | EKSクラスタARN |
| myapp-prod-cluster-endpoint | EKSクラスタAPIエンドポイント |
| myapp-prod-oidc-provider-arn | OIDCプロバイダーARN |
| myapp-prod-karpenter-node-role-arn | KarpenterノードロールARN |

#### Layer 3: app-stack

| 論理ID | CFnリソースタイプ | 概要 |
|--------|-----------------|------|
| ECRRepository | AWS::ECR::Repository | コンテナイメージレジストリ |
| DBSecret | AWS::SecretsManager::Secret | DB接続情報 |
| RedisSecret | AWS::SecretsManager::Secret | Redis接続情報 |
| APIKeySecret | AWS::SecretsManager::Secret | 外部APIキー |
| AppLogGroup | AWS::Logs::LogGroup | アプリログ |
| ControlPlaneLogGroup | AWS::Logs::LogGroup | コントロールプレーンログ |
| ALBLogBucket | AWS::S3::Bucket | ALBアクセスログ用S3 |
| AlertTopic | AWS::SNS::Topic | アラート通知SNS |
| CPUAlarm | AWS::CloudWatch::Alarm | CPU高負荷アラーム |
| MemoryAlarm | AWS::CloudWatch::Alarm | Memory高負荷アラーム |
| PodPendingAlarm | AWS::CloudWatch::Alarm | Pod Pendingアラーム |
| HPAMaxAlarm | AWS::CloudWatch::Alarm | HPA上限アラーム |
| Error5xxAlarm | AWS::CloudWatch::Alarm | 5xxエラー率アラーム |

### 5-3. スタック間の依存関係

```
network-stack
  └─ Outputs: VPC ID, Subnet IDs, SG IDs
        ↓ Fn::ImportValue
  eks-stack
    └─ Outputs: Cluster名, OIDC ARN, IAMロールARN
          ↓ Fn::ImportValue
      app-stack
        └─ Outputs: ECR URI, Secret ARN等
```

### 5-4. CFnで管理しないリソース

以下はK8sマニフェストまたはHelmで管理し、CFnの管理外とする。

| リソース | 管理方法 | タイミング |
|---------|---------|---------|
| Namespace | kubectl apply | eks-stackデプロイ後 |
| aws-authConfigMap | kubectl patch | eks-stackデプロイ後 |
| AWS Load Balancer Controller | Helm install | eks-stackデプロイ後 |
| External Secrets Operator | Helm install | eks-stackデプロイ後 |
| ClusterSecretStore | kubectl apply | ESO導入後 |
| Karpenter NodePool | kubectl apply | Karpenterアドオン導入後 |
| Karpenter EC2NodeClass | kubectl apply | Karpenterアドオン導入後 |
| HPA | kubectl apply | Deploymentデプロイ後 |
| PodDisruptionBudget | kubectl apply | Deploymentデプロイ後 |
| Deployment | kubectl apply | アプリデプロイ時 |
| Service | kubectl apply | アプリデプロイ時 |
| Ingress | kubectl apply | アプリデプロイ時 |
| ExternalSecret | kubectl apply | ESO導入後 |

### 5-5. CFnパラメータ設計

環境差異は`Parameters`セクションで吸収する。

| パラメータ名 | 型 | prod値 | stg値 |
|------------|-----|--------|-------|
| Env | String | prod | stg |
| EKSVersion | String | 1.30 | 1.30 |
| InitialNodeInstanceType | String | m5.xlarge | m5.large |
| InitialNodeDesiredSize | Number | 2 | 1 |

---

## 6. K8sマニフェスト変更一覧

オンプレからの変更差分をすべて網羅する。

### 6-1. Namespace

変更なし。`myapp` Namespaceを維持する。

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: myapp
```

### 6-2. Deployment

**変更点**:
- `image`をECR URIに変更
- `serviceAccountName`を追加
- `topologySpreadConstraints`を追加（マルチAZ分散）
- 環境変数のSecretリファレンスを変更（K8s Secret → ExternalSecretが作成するSecret）

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
  namespace: myapp
spec:
  replicas: 2
  selector:
    matchLabels:
      app: myapp
  template:
    metadata:
      labels:
        app: myapp
    spec:
      serviceAccountName: myapp-sa  # 追加
      topologySpreadConstraints:     # 追加（マルチAZ分散）
        - maxSkew: 1
          topologyKey: topology.kubernetes.io/zone
          whenUnsatisfiable: DoNotSchedule
          labelSelector:
            matchLabels:
              app: myapp
      containers:
        - name: myapp
          image: {AWS_ACCOUNT_ID}.dkr.ecr.ap-northeast-1.amazonaws.com/myapp-prod:latest  # 変更
          ports:
            - containerPort: 8080
          resources:
            requests:
              cpu: 250m
              memory: 256Mi
            limits:
              cpu: 500m
              memory: 512Mi
          env:
            - name: DB_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: myapp-secret  # ExternalSecretが作成するSecretを参照
                  key: DB_PASSWORD
          readinessProbe:
            httpGet:
              path: /healthz
              port: 8080
            initialDelaySeconds: 10
            periodSeconds: 5
          livenessProbe:
            httpGet:
              path: /healthz
              port: 8080
            initialDelaySeconds: 15
            periodSeconds: 10
```

### 6-3. Service

変更なし。ClusterIPのまま維持する。

```yaml
apiVersion: v1
kind: Service
metadata:
  name: myapp
  namespace: myapp
spec:
  selector:
    app: myapp
  ports:
    - port: 80
      targetPort: 8080
  type: ClusterIP
```

### 6-4. Ingress

**変更点**: Nginx IngressからALB Ingress（AWS Load Balancer Controller）に変更。

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: myapp
  namespace: myapp
  annotations:
    kubernetes.io/ingress.class: alb                          # 変更
    alb.ingress.kubernetes.io/scheme: internet-facing         # 追加
    alb.ingress.kubernetes.io/target-type: ip                 # 追加
    alb.ingress.kubernetes.io/certificate-arn: {ACM_CERT_ARN} # 追加
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTPS":443}]' # 追加
    alb.ingress.kubernetes.io/security-groups: {ALB_SG_ID}   # 追加
spec:
  rules:
    - host: myapp.example.com  # 変更（ドメイン変更）
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: myapp
                port:
                  number: 80
```

### 6-5. ServiceAccount

**新規追加**。IRSAのためのアノテーションを付与する。

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: myapp-sa
  namespace: myapp
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::{AWS_ACCOUNT_ID}:role/myapp-prod-app-role  # IRSAのIAMロールARN
```

---

## 7. スケーリング設計

### 7-1. スケーリング全体方針

クラウド化の最重要要件として、負荷変動に対して**自動で自律的にスケールする**構成を採用する。
オンプレで手動対応していたキャパシティ管理を完全に自動化する。

スケーリングは以下の2層で設計する。

```
┌─────────────────────────────────┐
│  Pod層       HPA                │  ← まずPodが増える
│  (アプリのスケール)               │
├─────────────────────────────────┤
│  ノード層    Karpenter           │  ← Podが乗り切れなくなったらノードが増える
│  (インフラのスケール)             │
└─────────────────────────────────┘
```

### 7-2. Podスケーリング（HPA）

#### 設定値

| 項目 | 設定値 |
|------|--------|
| 最小レプリカ数 | 2 |
| 最大レプリカ数 | 10 |
| スケールアウト指標（CPU） | 使用率60% |
| スケールアウト指標（Memory） | 使用率70% |
| スケールイン安定化時間 | 300秒 |

#### マニフェスト

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: myapp-hpa
  namespace: myapp
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: myapp
  minReplicas: 2
  maxReplicas: 10
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 60
    - type: Resource
      resource:
        name: memory
        target:
          type: Utilization
          averageUtilization: 70
  behavior:
    scaleIn:
      stabilizationWindowSeconds: 300
```

### 7-3. ノードスケーリング（Karpenter）

Cluster AutoscalerではなくKarpenterを採用する。

**採用理由**:
- ノード起動速度が速い（秒単位 vs 分単位）
- スポットインスタンスの自動フォールバックが容易
- CFnの`AWS::EKS::Addon`で管理可能

#### NodePool

```yaml
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: default
spec:
  template:
    spec:
      requirements:
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["spot", "on-demand"]
        - key: node.kubernetes.io/instance-category
          operator: In
          values: ["c", "m", "r"]
        - key: kubernetes.io/arch
          operator: In
          values: ["amd64"]
      nodeClassRef:
        name: default
  limits:
    cpu: "100"
    memory: 400Gi
  disruption:
    consolidationPolicy: WhenEmptyOrUnderutilized
    consolidateAfter: 30s
```

#### EC2NodeClass

```yaml
apiVersion: karpenter.k8s.aws/v1
kind: EC2NodeClass
metadata:
  name: default
spec:
  amiSelectorTerms:
    - alias: al2023@latest
  subnetSelectorTerms:
    - tags:
        karpenter.sh/discovery: myapp-prod-eks-cluster
  securityGroupSelectorTerms:
    - tags:
        karpenter.sh/discovery: myapp-prod-eks-cluster
  role: myapp-prod-karpenter-node-role
```

### 7-4. スポットインスタンス対応

| 対応項目 | 設定内容 |
|---------|---------|
| Spot/On-Demand優先順 | Spot優先、フォールバックでOn-Demand |
| Spot中断対応 | Karpenterが2分前通知を検知し自動drain |
| PDB | minAvailable: 1（最低1Pod稼働を保証） |
| AZ分散 | topologySpreadConstraintsで3AZに強制分散 |

#### PodDisruptionBudget

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: myapp-pdb
  namespace: myapp
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app: myapp
```

### 7-5. スケーリング監視

| 監視項目 | 閾値 | アクション |
|---------|------|-----------|
| HPAがmaxReplicasに張り付き | 5分以上 | アラート → maxReplicas見直し |
| PendingのままのPod | 10分以上 | アラート → Karpenter設定確認 |
| Karpenterノードが上限到達 | - | アラート → limitsの引き上げ検討 |
| Spot中断率 | 30%以上 | On-Demand比率の変更を検討 |

すべてCloudWatch Alarmで実装し、CFnで管理する。

---

## 8. デプロイ手順

**本章は実装時にそのまま実行できる粒度で記述する。**

### 8-1. 事前準備

```bash
# AWS CLIのプロファイル設定確認
aws sts get-caller-identity

# kubectlバージョン確認（1.30.x）
kubectl version --client

# Helmバージョン確認（v3.x）
helm version

# 環境変数設定
export AWS_ACCOUNT_ID=XXXXXXXXXXXX
export AWS_REGION=ap-northeast-1
export ENV=prod
export SERVICE_NAME=myapp
export CLUSTER_NAME=${SERVICE_NAME}-${ENV}-eks-cluster
```

### 8-2. CFnスタックデプロイ

#### Step 1: network-stack

```bash
aws cloudformation deploy \
  --stack-name ${SERVICE_NAME}-${ENV}-network-stack \
  --template-file cfn/network-stack.yaml \
  --parameter-overrides \
    Env=${ENV} \
  --region ${AWS_REGION} \
  --on-failure ROLLBACK
```

#### Step 2: eks-stack

```bash
aws cloudformation deploy \
  --stack-name ${SERVICE_NAME}-${ENV}-eks-stack \
  --template-file cfn/eks-stack.yaml \
  --parameter-overrides \
    Env=${ENV} \
    EKSVersion=1.30 \
    InitialNodeInstanceType=m5.xlarge \
    InitialNodeDesiredSize=2 \
  --capabilities CAPABILITY_NAMED_IAM \
  --region ${AWS_REGION} \
  --on-failure ROLLBACK
```

#### Step 3: app-stack

```bash
aws cloudformation deploy \
  --stack-name ${SERVICE_NAME}-${ENV}-app-stack \
  --template-file cfn/app-stack.yaml \
  --parameter-overrides \
    Env=${ENV} \
  --capabilities CAPABILITY_NAMED_IAM \
  --region ${AWS_REGION} \
  --on-failure ROLLBACK
```

### 8-3. kubeconfigの更新

```bash
aws eks update-kubeconfig \
  --name ${CLUSTER_NAME} \
  --region ${AWS_REGION}

# 接続確認
kubectl get nodes
```

### 8-4. aws-authの設定

```bash
kubectl patch configmap/aws-auth \
  -n kube-system \
  --patch "$(cat k8s/aws-auth-patch.yaml)"
```

`aws-auth-patch.yaml`:

```yaml
data:
  mapRoles: |
    - rolearn: arn:aws:iam::{AWS_ACCOUNT_ID}:role/myapp-prod-karpenter-node-role
      username: system:node:{{EC2PrivateDNSName}}
      groups:
        - system:bootstrappers
        - system:nodes
```

### 8-5. AWS Load Balancer Controllerのインストール

```bash
helm repo add eks https://aws.github.io/eks-charts
helm repo update

helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=${CLUSTER_NAME} \
  --set serviceAccount.create=true \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=arn:aws:iam::${AWS_ACCOUNT_ID}:role/myapp-prod-alb-controller-role \
  --version 1.8.x

# 確認
kubectl get deployment -n kube-system aws-load-balancer-controller
```

### 8-6. External Secrets Operatorのインストール

```bash
helm repo add external-secrets https://charts.external-secrets.io
helm repo update

helm install external-secrets external-secrets/external-secrets \
  -n external-secrets \
  --create-namespace \
  --version 0.9.x

# 確認
kubectl get pods -n external-secrets
```

### 8-7. Karpenter NodePool / EC2NodeClassの適用

```bash
kubectl apply -f k8s/karpenter-nodepool.yaml
kubectl apply -f k8s/karpenter-ec2nodeclass.yaml

# 確認
kubectl get nodepool
kubectl get ec2nodeclass
```

### 8-8. Namespaceとアプリケーションリソースの適用

```bash
# Namespace
kubectl apply -f k8s/namespace.yaml

# ServiceAccount
kubectl apply -f k8s/serviceaccount.yaml

# ClusterSecretStore
kubectl apply -f k8s/cluster-secret-store.yaml

# ExternalSecret
kubectl apply -f k8s/external-secret.yaml

# Deployment / Service / Ingress
kubectl apply -f k8s/deployment.yaml
kubectl apply -f k8s/service.yaml
kubectl apply -f k8s/ingress.yaml

# HPA / PDB
kubectl apply -f k8s/hpa.yaml
kubectl apply -f k8s/pdb.yaml
```

### 8-9. ECRへのイメージPush

```bash
# ECRログイン
aws ecr get-login-password --region ${AWS_REGION} | \
  docker login --username AWS --password-stdin \
  ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com

# タグ付けとPush
docker tag myapp:latest \
  ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/myapp-prod:latest

docker push \
  ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/myapp-prod:latest
```

---

## 9. テスト・受け入れ基準

### 9-1. インフラ確認

| 確認項目 | 確認方法 | 合格基準 |
|---------|---------|---------|
| CFnスタック全3つが正常完了 | AWSコンソール or `aws cloudformation describe-stacks` | STATUSがCREATE_COMPLETE |
| EKSノードがReady | `kubectl get nodes` | 全ノードがReady |
| EKSアドオンが正常 | `aws eks describe-addon` | STATUSがACTIVE |
| Karpenter動作確認 | `kubectl get pods -n kube-system` | Karpenter PodがRunning |

### 9-2. アプリケーション動作確認

| 確認項目 | 確認方法 | 合格基準 |
|---------|---------|---------|
| Podが起動している | `kubectl get pods -n myapp` | 全PodがRunning |
| ヘルスチェック疎通 | `kubectl exec -it {pod} -- curl localhost:8080/healthz` | HTTP 200応答 |
| DB接続確認 | アプリログ確認 | 接続エラーなし |
| Redis接続確認 | アプリログ確認 | 接続エラーなし |
| ExternalSecretの同期 | `kubectl get externalsecret -n myapp` | STATUS: SecretSynced |
| ALB経由のHTTPS疎通 | `curl https://myapp.example.com/healthz` | HTTP 200応答 |

### 9-3. スケーリング動作確認

| 確認項目 | 確認方法 | 合格基準 |
|---------|---------|---------|
| HPAが正常に作成されている | `kubectl get hpa -n myapp` | MINPODS/MAXPODS が正しい値 |
| 負荷テストでPodがスケールアウト | `kubectl run -i --tty load-gen --image=busybox -- /bin/sh`でCPU負荷をかける | Pod数が増加する |
| 負荷解放後にスケールイン | 負荷を止めて300秒待つ | Pod数がminReplicasに戻る |
| Karpenterがノードを追加 | Pod数増加時に`kubectl get nodes`を確認 | 新しいノードが追加される |
| Karpenterがノードを削除 | 負荷解放後に`kubectl get nodes`を確認 | 不要なノードが削除される |

### 9-4. 受け入れ基準（Go/NoGo判定）

以下をすべて満たした場合のみGOとする。

- [ ] CFnスタック3つがすべてCREATE_COMPLETE
- [ ] EKSノードが全台Ready
- [ ] Podがminimum 2台Running
- [ ] ALB経由でHTTPS 200応答が返ること
- [ ] DB・Redis接続エラーがないこと
- [ ] HPAが正しく設定されていること
- [ ] Karpenterのスケールアウトが動作すること
- [ ] CloudWatchにメトリクス・ログが届いていること
- [ ] アラームが正しく設定されていること

---

## 10. 非機能要件

### 10-1. 可用性

| 項目 | 要件 | 実現方法 |
|------|------|---------|
| 目標SLA | 99.9%（月間ダウンタイム約43分以内） | マルチAZ構成、最小レプリカ数2 |
| AZ障害耐性 | 1AZ障害を許容 | 3AZにPodを分散 |
| ノード障害耐性 | 1ノード障害を許容 | PDB設定、Karpenterによる自動補充 |
| コントロールプレーン | EKSマネージドにより自動冗長化 | AWSが管理 |

### 10-2. セキュリティ

| 項目 | 要件 | 実現方法 |
|------|------|---------|
| コンテナイメージ | 脆弱性スキャン | ECRの組み込みスキャン機能（プッシュ時自動） |
| Podの権限 | 最小権限 | IRSA + PodのServiceAccount指定 |
| ネットワーク | ノードはプライベートサブネット | パブリックSubnetにはALBのみ配置 |
| シークレット | 平文管理禁止 | Secrets Manager + External Secrets Operator |
| Pod Security | 制約適用 | Pod Security Standards: restricted |
| API Serverアクセス | 制限 | エンドポイントをパブリック+プライベート、IP制限を設定 |

### 10-3. コスト管理

| 項目 | 対策 |
|------|------|
| コンピュート | スポットインスタンス優先使用 |
| アイドルノード | Karpenterのconsolidationで自動削除（30秒） |
| スケールイン | HPAの安定化時間を300秒に設定（過剰スケールアウト防止） |
| ノード上限 | Karpenterのlimits（CPU:100, Memory:400Gi）でコスト上限を設定 |
| ログ保持 | ロググループの保持期間を30〜90日に限定 |

### 10-4. 運用・保守

| 項目 | 内容 |
|------|------|
| Kubernetesバージョンアップ | EKSの標準サポート期間内に対応（14ヶ月ごとにマイナーバージョンアップ） |
| ノードOSパッチ | Karpenterのdriftを使用し自動ローリング更新 |
| 設定変更 | CFnのChangeSetを使用し差分確認後に適用 |
| アプリデプロイ | `kubectl set image`またはマニフェスト更新 → `kubectl apply` |
| ロールバック | `kubectl rollout undo deployment/myapp` |

---

*本仕様書のすべての設定値・確定値はTBDなしで記載済みであること。実装時に変更が生じた場合は本文書を更新すること。*

---

## 付録A: CFnテンプレート

### A-1. network-stack.yaml

```yaml
AWSTemplateFormatVersion: "2010-09-09"
Description: "myapp network stack - VPC, Subnets, SG, IGW, NAT"

Parameters:
  Env:
    Type: String
    AllowedValues: [prod, stg]
  ServiceName:
    Type: String
    Default: myapp

Mappings:
  EnvConfig:
    prod:
      VpcCidr: "10.0.0.0/16"
      PubSubnet1a: "10.0.0.0/24"
      PubSubnet1c: "10.0.1.0/24"
      PubSubnet1d: "10.0.2.0/24"
      PriSubnet1a: "10.0.10.0/24"
      PriSubnet1c: "10.0.11.0/24"
      PriSubnet1d: "10.0.12.0/24"
    stg:
      VpcCidr: "10.1.0.0/16"
      PubSubnet1a: "10.1.0.0/24"
      PubSubnet1c: "10.1.1.0/24"
      PubSubnet1d: "10.1.2.0/24"
      PriSubnet1a: "10.1.10.0/24"
      PriSubnet1c: "10.1.11.0/24"
      PriSubnet1d: "10.1.12.0/24"

Resources:
  # ─────────────────────────────
  # VPC
  # ─────────────────────────────
  VPC:
    Type: AWS::EC2::VPC
    Properties:
      CidrBlock: !FindInMap [EnvConfig, !Ref Env, VpcCidr]
      EnableDnsHostnames: true
      EnableDnsSupport: true
      Tags:
        - Key: Name
          Value: !Sub "${ServiceName}-${Env}-vpc"

  # ─────────────────────────────
  # パブリックサブネット
  # ─────────────────────────────
  PublicSubnet1a:
    Type: AWS::EC2::Subnet
    Properties:
      VpcId: !Ref VPC
      CidrBlock: !FindInMap [EnvConfig, !Ref Env, PubSubnet1a]
      AvailabilityZone: ap-northeast-1a
      MapPublicIpOnLaunch: true
      Tags:
        - Key: Name
          Value: !Sub "${ServiceName}-${Env}-public-1a"
        - Key: kubernetes.io/role/elb
          Value: "1"

  PublicSubnet1c:
    Type: AWS::EC2::Subnet
    Properties:
      VpcId: !Ref VPC
      CidrBlock: !FindInMap [EnvConfig, !Ref Env, PubSubnet1c]
      AvailabilityZone: ap-northeast-1c
      MapPublicIpOnLaunch: true
      Tags:
        - Key: Name
          Value: !Sub "${ServiceName}-${Env}-public-1c"
        - Key: kubernetes.io/role/elb
          Value: "1"

  PublicSubnet1d:
    Type: AWS::EC2::Subnet
    Properties:
      VpcId: !Ref VPC
      CidrBlock: !FindInMap [EnvConfig, !Ref Env, PubSubnet1d]
      AvailabilityZone: ap-northeast-1d
      MapPublicIpOnLaunch: true
      Tags:
        - Key: Name
          Value: !Sub "${ServiceName}-${Env}-public-1d"
        - Key: kubernetes.io/role/elb
          Value: "1"

  # ─────────────────────────────
  # プライベートサブネット
  # ─────────────────────────────
  PrivateSubnet1a:
    Type: AWS::EC2::Subnet
    Properties:
      VpcId: !Ref VPC
      CidrBlock: !FindInMap [EnvConfig, !Ref Env, PriSubnet1a]
      AvailabilityZone: ap-northeast-1a
      Tags:
        - Key: Name
          Value: !Sub "${ServiceName}-${Env}-private-1a"
        - Key: kubernetes.io/role/internal-elb
          Value: "1"
        - Key: !Sub "karpenter.sh/discovery"
          Value: !Sub "${ServiceName}-${Env}-eks-cluster"

  PrivateSubnet1c:
    Type: AWS::EC2::Subnet
    Properties:
      VpcId: !Ref VPC
      CidrBlock: !FindInMap [EnvConfig, !Ref Env, PriSubnet1c]
      AvailabilityZone: ap-northeast-1c
      Tags:
        - Key: Name
          Value: !Sub "${ServiceName}-${Env}-private-1c"
        - Key: kubernetes.io/role/internal-elb
          Value: "1"
        - Key: !Sub "karpenter.sh/discovery"
          Value: !Sub "${ServiceName}-${Env}-eks-cluster"

  PrivateSubnet1d:
    Type: AWS::EC2::Subnet
    Properties:
      VpcId: !Ref VPC
      CidrBlock: !FindInMap [EnvConfig, !Ref Env, PriSubnet1d]
      AvailabilityZone: ap-northeast-1d
      Tags:
        - Key: Name
          Value: !Sub "${ServiceName}-${Env}-private-1d"
        - Key: kubernetes.io/role/internal-elb
          Value: "1"
        - Key: !Sub "karpenter.sh/discovery"
          Value: !Sub "${ServiceName}-${Env}-eks-cluster"

  # ─────────────────────────────
  # Internet Gateway
  # ─────────────────────────────
  InternetGateway:
    Type: AWS::EC2::InternetGateway
    Properties:
      Tags:
        - Key: Name
          Value: !Sub "${ServiceName}-${Env}-igw"

  VPCGatewayAttachment:
    Type: AWS::EC2::VPCGatewayAttachment
    Properties:
      VpcId: !Ref VPC
      InternetGatewayId: !Ref InternetGateway

  # ─────────────────────────────
  # NAT Gateway（1a, 1c の2つ）
  # ─────────────────────────────
  EIPForNat1a:
    Type: AWS::EC2::EIP
    Properties:
      Domain: vpc

  EIPForNat1c:
    Type: AWS::EC2::EIP
    Properties:
      Domain: vpc

  NatGateway1a:
    Type: AWS::EC2::NatGateway
    Properties:
      AllocationId: !GetAtt EIPForNat1a.AllocationId
      SubnetId: !Ref PublicSubnet1a
      Tags:
        - Key: Name
          Value: !Sub "${ServiceName}-${Env}-nat-1a"

  NatGateway1c:
    Type: AWS::EC2::NatGateway
    Properties:
      AllocationId: !GetAtt EIPForNat1c.AllocationId
      SubnetId: !Ref PublicSubnet1c
      Tags:
        - Key: Name
          Value: !Sub "${ServiceName}-${Env}-nat-1c"

  # ─────────────────────────────
  # Route Tables
  # ─────────────────────────────
  PublicRouteTable:
    Type: AWS::EC2::RouteTable
    Properties:
      VpcId: !Ref VPC
      Tags:
        - Key: Name
          Value: !Sub "${ServiceName}-${Env}-public-rtb"

  PublicRoute:
    Type: AWS::EC2::Route
    DependsOn: VPCGatewayAttachment
    Properties:
      RouteTableId: !Ref PublicRouteTable
      DestinationCidrBlock: "0.0.0.0/0"
      GatewayId: !Ref InternetGateway

  PublicSubnet1aRTAssoc:
    Type: AWS::EC2::SubnetRouteTableAssociation
    Properties:
      SubnetId: !Ref PublicSubnet1a
      RouteTableId: !Ref PublicRouteTable

  PublicSubnet1cRTAssoc:
    Type: AWS::EC2::SubnetRouteTableAssociation
    Properties:
      SubnetId: !Ref PublicSubnet1c
      RouteTableId: !Ref PublicRouteTable

  PublicSubnet1dRTAssoc:
    Type: AWS::EC2::SubnetRouteTableAssociation
    Properties:
      SubnetId: !Ref PublicSubnet1d
      RouteTableId: !Ref PublicRouteTable

  PrivateRouteTable1a:
    Type: AWS::EC2::RouteTable
    Properties:
      VpcId: !Ref VPC
      Tags:
        - Key: Name
          Value: !Sub "${ServiceName}-${Env}-private-rtb-1a"

  PrivateRoute1a:
    Type: AWS::EC2::Route
    Properties:
      RouteTableId: !Ref PrivateRouteTable1a
      DestinationCidrBlock: "0.0.0.0/0"
      NatGatewayId: !Ref NatGateway1a

  PrivateSubnet1aRTAssoc:
    Type: AWS::EC2::SubnetRouteTableAssociation
    Properties:
      SubnetId: !Ref PrivateSubnet1a
      RouteTableId: !Ref PrivateRouteTable1a

  PrivateRouteTable1c:
    Type: AWS::EC2::RouteTable
    Properties:
      VpcId: !Ref VPC
      Tags:
        - Key: Name
          Value: !Sub "${ServiceName}-${Env}-private-rtb-1c"

  PrivateRoute1c:
    Type: AWS::EC2::Route
    Properties:
      RouteTableId: !Ref PrivateRouteTable1c
      DestinationCidrBlock: "0.0.0.0/0"
      NatGatewayId: !Ref NatGateway1c

  PrivateSubnet1cRTAssoc:
    Type: AWS::EC2::SubnetRouteTableAssociation
    Properties:
      SubnetId: !Ref PrivateSubnet1c
      RouteTableId: !Ref PrivateRouteTable1c

  PrivateRouteTable1d:
    Type: AWS::EC2::RouteTable
    Properties:
      VpcId: !Ref VPC
      Tags:
        - Key: Name
          Value: !Sub "${ServiceName}-${Env}-private-rtb-1d"

  PrivateRoute1d:
    Type: AWS::EC2::Route
    Properties:
      RouteTableId: !Ref PrivateRouteTable1d
      DestinationCidrBlock: "0.0.0.0/0"
      NatGatewayId: !Ref NatGateway1c  # 1dはNAT1cにフォールバック

  PrivateSubnet1dRTAssoc:
    Type: AWS::EC2::SubnetRouteTableAssociation
    Properties:
      SubnetId: !Ref PrivateSubnet1d
      RouteTableId: !Ref PrivateRouteTable1d

  # ─────────────────────────────
  # Security Groups
  # ─────────────────────────────
  ALBSecurityGroup:
    Type: AWS::EC2::SecurityGroup
    Properties:
      GroupDescription: "Security group for ALB"
      VpcId: !Ref VPC
      SecurityGroupIngress:
        - IpProtocol: tcp
          FromPort: 443
          ToPort: 443
          CidrIp: "0.0.0.0/0"
      Tags:
        - Key: Name
          Value: !Sub "${ServiceName}-${Env}-alb-sg"

  NodeSecurityGroup:
    Type: AWS::EC2::SecurityGroup
    Properties:
      GroupDescription: "Security group for EKS worker nodes"
      VpcId: !Ref VPC
      SecurityGroupIngress:
        - IpProtocol: -1
          SourceSecurityGroupId: !Ref ALBSecurityGroup
        - IpProtocol: -1
          SourceSecurityGroupId: !Ref ClusterSecurityGroup
      SecurityGroupEgress:
        - IpProtocol: -1
          CidrIp: "0.0.0.0/0"
      Tags:
        - Key: Name
          Value: !Sub "${ServiceName}-${Env}-node-sg"
        - Key: !Sub "karpenter.sh/discovery"
          Value: !Sub "${ServiceName}-${Env}-eks-cluster"

  NodeSelfIngress:
    Type: AWS::EC2::SecurityGroupIngress
    Properties:
      GroupId: !Ref NodeSecurityGroup
      IpProtocol: -1
      SourceSecurityGroupId: !Ref NodeSecurityGroup

  ClusterSecurityGroup:
    Type: AWS::EC2::SecurityGroup
    Properties:
      GroupDescription: "Security group for EKS control plane"
      VpcId: !Ref VPC
      SecurityGroupIngress:
        - IpProtocol: tcp
          FromPort: 443
          ToPort: 443
          SourceSecurityGroupId: !Ref NodeSecurityGroup
      Tags:
        - Key: Name
          Value: !Sub "${ServiceName}-${Env}-cluster-sg"

Outputs:
  VpcId:
    Value: !Ref VPC
    Export:
      Name: !Sub "${ServiceName}-${Env}-vpc-id"

  PrivateSubnet1a:
    Value: !Ref PrivateSubnet1a
    Export:
      Name: !Sub "${ServiceName}-${Env}-private-subnet-1a"

  PrivateSubnet1c:
    Value: !Ref PrivateSubnet1c
    Export:
      Name: !Sub "${ServiceName}-${Env}-private-subnet-1c"

  PrivateSubnet1d:
    Value: !Ref PrivateSubnet1d
    Export:
      Name: !Sub "${ServiceName}-${Env}-private-subnet-1d"

  PublicSubnet1a:
    Value: !Ref PublicSubnet1a
    Export:
      Name: !Sub "${ServiceName}-${Env}-public-subnet-1a"

  PublicSubnet1c:
    Value: !Ref PublicSubnet1c
    Export:
      Name: !Sub "${ServiceName}-${Env}-public-subnet-1c"

  PublicSubnet1d:
    Value: !Ref PublicSubnet1d
    Export:
      Name: !Sub "${ServiceName}-${Env}-public-subnet-1d"

  ALBSecurityGroupId:
    Value: !Ref ALBSecurityGroup
    Export:
      Name: !Sub "${ServiceName}-${Env}-alb-sg-id"

  NodeSecurityGroupId:
    Value: !Ref NodeSecurityGroup
    Export:
      Name: !Sub "${ServiceName}-${Env}-node-sg-id"

  ClusterSecurityGroupId:
    Value: !Ref ClusterSecurityGroup
    Export:
      Name: !Sub "${ServiceName}-${Env}-cluster-sg-id"
```

---

### A-2. eks-stack.yaml

```yaml
AWSTemplateFormatVersion: "2010-09-09"
Description: "myapp EKS stack - Cluster, NodeGroup, IAM, OIDC, Addons"

Parameters:
  Env:
    Type: String
    AllowedValues: [prod, stg]
  ServiceName:
    Type: String
    Default: myapp
  EKSVersion:
    Type: String
    Default: "1.30"
  InitialNodeInstanceType:
    Type: String
    Default: m5.xlarge
  InitialNodeDesiredSize:
    Type: Number
    Default: 2

Resources:
  # ─────────────────────────────
  # EKS Cluster IAM Role
  # ─────────────────────────────
  EKSClusterRole:
    Type: AWS::IAM::Role
    Properties:
      RoleName: !Sub "${ServiceName}-${Env}-eks-cluster-role"
      AssumeRolePolicyDocument:
        Version: "2012-10-17"
        Statement:
          - Effect: Allow
            Principal:
              Service: eks.amazonaws.com
            Action: sts:AssumeRole
      ManagedPolicyArns:
        - arn:aws:iam::aws:policy/AmazonEKSClusterPolicy

  # ─────────────────────────────
  # EKS Cluster
  # ─────────────────────────────
  EKSCluster:
    Type: AWS::EKS::Cluster
    Properties:
      Name: !Sub "${ServiceName}-${Env}-eks-cluster"
      Version: !Ref EKSVersion
      RoleArn: !GetAtt EKSClusterRole.Arn
      ResourcesVpcConfig:
        SubnetIds:
          - !ImportValue
            Fn::Sub: "${ServiceName}-${Env}-private-subnet-1a"
          - !ImportValue
            Fn::Sub: "${ServiceName}-${Env}-private-subnet-1c"
          - !ImportValue
            Fn::Sub: "${ServiceName}-${Env}-private-subnet-1d"
        SecurityGroupIds:
          - !ImportValue
            Fn::Sub: "${ServiceName}-${Env}-cluster-sg-id"
        EndpointPublicAccess: true
        EndpointPrivateAccess: true
      Logging:
        ClusterLogging:
          EnabledTypes:
            - Type: api
            - Type: audit
            - Type: authenticator
            - Type: controllerManager
            - Type: scheduler
      Tags:
        - Key: !Sub "karpenter.sh/discovery"
          Value: !Sub "${ServiceName}-${Env}-eks-cluster"

  # ─────────────────────────────
  # OIDC Provider（IRSA用）
  # ─────────────────────────────
  OIDCProvider:
    Type: AWS::IAM::OIDCProvider
    Properties:
      Url: !GetAtt EKSCluster.OpenIdConnectIssuerUrl
      ClientIdList:
        - sts.amazonaws.com
      ThumbprintList:
        - "9e99a48a9960b14926bb7f3b02e22da2b0ab7280"

  # ─────────────────────────────
  # Karpenter Node IAM Role
  # ─────────────────────────────
  KarpenterNodeRole:
    Type: AWS::IAM::Role
    Properties:
      RoleName: !Sub "${ServiceName}-${Env}-karpenter-node-role"
      AssumeRolePolicyDocument:
        Version: "2012-10-17"
        Statement:
          - Effect: Allow
            Principal:
              Service: ec2.amazonaws.com
            Action: sts:AssumeRole
      ManagedPolicyArns:
        - arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy
        - arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy
        - arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly
        - arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore

  KarpenterNodeInstanceProfile:
    Type: AWS::IAM::InstanceProfile
    Properties:
      InstanceProfileName: !Sub "${ServiceName}-${Env}-karpenter-node-profile"
      Roles:
        - !Ref KarpenterNodeRole

  # ─────────────────────────────
  # Karpenter Controller IAM Role（IRSA）
  # ─────────────────────────────
  KarpenterControllerRole:
    Type: AWS::IAM::Role
    Properties:
      RoleName: !Sub "${ServiceName}-${Env}-karpenter-controller-role"
      AssumeRolePolicyDocument:
        Version: "2012-10-17"
        Statement:
          - Effect: Allow
            Principal:
              Federated: !Ref OIDCProvider
            Action: sts:AssumeRoleWithWebIdentity
            Condition:
              StringEquals:
                !Sub
                  - "${OIDCUrl}:sub"
                  - OIDCUrl: !Select [1, !Split ["//", !GetAtt EKSCluster.OpenIdConnectIssuerUrl]]
                : "system:serviceaccount:kube-system:karpenter"
      Policies:
        - PolicyName: KarpenterControllerPolicy
          PolicyDocument:
            Version: "2012-10-17"
            Statement:
              - Effect: Allow
                Action:
                  - ec2:CreateFleet
                  - ec2:CreateLaunchTemplate
                  - ec2:CreateTags
                  - ec2:DeleteLaunchTemplate
                  - ec2:DescribeAvailabilityZones
                  - ec2:DescribeImages
                  - ec2:DescribeInstances
                  - ec2:DescribeInstanceTypeOfferings
                  - ec2:DescribeInstanceTypes
                  - ec2:DescribeLaunchTemplates
                  - ec2:DescribeSecurityGroups
                  - ec2:DescribeSpotPriceHistory
                  - ec2:DescribeSubnets
                  - ec2:RunInstances
                  - ec2:TerminateInstances
                  - iam:PassRole
                  - eks:DescribeCluster
                  - pricing:GetProducts
                  - ssm:GetParameter
                Resource: "*"

  # ─────────────────────────────
  # ALB Controller IAM Role（IRSA）
  # ─────────────────────────────
  ALBControllerRole:
    Type: AWS::IAM::Role
    Properties:
      RoleName: !Sub "${ServiceName}-${Env}-alb-controller-role"
      AssumeRolePolicyDocument:
        Version: "2012-10-17"
        Statement:
          - Effect: Allow
            Principal:
              Federated: !Ref OIDCProvider
            Action: sts:AssumeRoleWithWebIdentity
            Condition:
              StringEquals:
                !Sub
                  - "${OIDCUrl}:sub"
                  - OIDCUrl: !Select [1, !Split ["//", !GetAtt EKSCluster.OpenIdConnectIssuerUrl]]
                : "system:serviceaccount:kube-system:aws-load-balancer-controller"
      ManagedPolicyArns:
        - arn:aws:iam::aws:policy/ElasticLoadBalancingFullAccess
      Policies:
        - PolicyName: ALBControllerAdditionalPolicy
          PolicyDocument:
            Version: "2012-10-17"
            Statement:
              - Effect: Allow
                Action:
                  - ec2:DescribeAccountAttributes
                  - ec2:DescribeAddresses
                  - ec2:DescribeInternetGateways
                  - ec2:DescribeVpcs
                  - ec2:DescribeSubnets
                  - ec2:DescribeSecurityGroups
                  - ec2:DescribeInstances
                  - ec2:DescribeNetworkInterfaces
                  - ec2:DescribeTags
                  - ec2:CreateSecurityGroup
                  - ec2:CreateTags
                  - ec2:DeleteTags
                  - ec2:AuthorizeSecurityGroupIngress
                  - ec2:RevokeSecurityGroupIngress
                  - ec2:DeleteSecurityGroup
                  - cognito-idp:DescribeUserPoolClient
                  - acm:ListCertificates
                  - acm:DescribeCertificate
                  - shield:DescribeProtection
                  - wafv2:GetWebACL
                  - wafv2:AssociateWebACL
                Resource: "*"

  # ─────────────────────────────
  # App ServiceAccount IAM Role（IRSA）
  # ─────────────────────────────
  AppServiceAccountRole:
    Type: AWS::IAM::Role
    Properties:
      RoleName: !Sub "${ServiceName}-${Env}-app-role"
      AssumeRolePolicyDocument:
        Version: "2012-10-17"
        Statement:
          - Effect: Allow
            Principal:
              Federated: !Ref OIDCProvider
            Action: sts:AssumeRoleWithWebIdentity
            Condition:
              StringEquals:
                !Sub
                  - "${OIDCUrl}:sub"
                  - OIDCUrl: !Select [1, !Split ["//", !GetAtt EKSCluster.OpenIdConnectIssuerUrl]]
                : !Sub "system:serviceaccount:${ServiceName}:${ServiceName}-sa"
      Policies:
        - PolicyName: AppSecretsPolicy
          PolicyDocument:
            Version: "2012-10-17"
            Statement:
              - Effect: Allow
                Action:
                  - secretsmanager:GetSecretValue
                  - secretsmanager:DescribeSecret
                Resource: !Sub "arn:aws:secretsmanager:ap-northeast-1:${AWS::AccountId}:secret:${ServiceName}/${Env}/*"

  # ─────────────────────────────
  # 初期ノードグループ（Karpenter用）
  # ─────────────────────────────
  InitialNodeGroupRole:
    Type: AWS::IAM::Role
    Properties:
      RoleName: !Sub "${ServiceName}-${Env}-initial-node-role"
      AssumeRolePolicyDocument:
        Version: "2012-10-17"
        Statement:
          - Effect: Allow
            Principal:
              Service: ec2.amazonaws.com
            Action: sts:AssumeRole
      ManagedPolicyArns:
        - arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy
        - arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy
        - arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly
        - arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore

  InitialNodeGroup:
    Type: AWS::EKS::Nodegroup
    DependsOn: EKSCluster
    Properties:
      NodegroupName: !Sub "${ServiceName}-${Env}-initial-ng"
      ClusterName: !Ref EKSCluster
      NodeRole: !GetAtt InitialNodeGroupRole.Arn
      Subnets:
        - !ImportValue
          Fn::Sub: "${ServiceName}-${Env}-private-subnet-1a"
        - !ImportValue
          Fn::Sub: "${ServiceName}-${Env}-private-subnet-1c"
      ScalingConfig:
        MinSize: 1
        MaxSize: 3
        DesiredSize: !Ref InitialNodeDesiredSize
      InstanceTypes:
        - !Ref InitialNodeInstanceType
      AmiType: AL2023_x86_64_STANDARD
      Labels:
        role: system
      Taints:
        - Key: CriticalAddonsOnly
          Value: "true"
          Effect: NO_SCHEDULE

  # ─────────────────────────────
  # EKS Addons
  # ─────────────────────────────
  VPCCNIAddon:
    Type: AWS::EKS::Addon
    DependsOn: InitialNodeGroup
    Properties:
      ClusterName: !Ref EKSCluster
      AddonName: vpc-cni
      AddonVersion: v1.18.3-eksbuild.2
      ResolveConflicts: OVERWRITE

  CoreDNSAddon:
    Type: AWS::EKS::Addon
    DependsOn: VPCCNIAddon
    Properties:
      ClusterName: !Ref EKSCluster
      AddonName: coredns
      AddonVersion: v1.11.1-eksbuild.9
      ResolveConflicts: OVERWRITE

  KubeProxyAddon:
    Type: AWS::EKS::Addon
    DependsOn: InitialNodeGroup
    Properties:
      ClusterName: !Ref EKSCluster
      AddonName: kube-proxy
      AddonVersion: v1.30.0-eksbuild.3
      ResolveConflicts: OVERWRITE

  EBSCSIDriverAddon:
    Type: AWS::EKS::Addon
    DependsOn: InitialNodeGroup
    Properties:
      ClusterName: !Ref EKSCluster
      AddonName: aws-ebs-csi-driver
      AddonVersion: v1.31.0-eksbuild.1
      ResolveConflicts: OVERWRITE

  KarpenterAddon:
    Type: AWS::EKS::Addon
    DependsOn:
      - CoreDNSAddon
      - KarpenterControllerRole
    Properties:
      ClusterName: !Ref EKSCluster
      AddonName: karpenter
      AddonVersion: v1.0.1-eksbuild.1
      ResolveConflicts: OVERWRITE
      ServiceAccountRoleArn: !GetAtt KarpenterControllerRole.Arn

Outputs:
  ClusterName:
    Value: !Ref EKSCluster
    Export:
      Name: !Sub "${ServiceName}-${Env}-cluster-name"

  ClusterArn:
    Value: !GetAtt EKSCluster.Arn
    Export:
      Name: !Sub "${ServiceName}-${Env}-cluster-arn"

  ClusterEndpoint:
    Value: !GetAtt EKSCluster.Endpoint
    Export:
      Name: !Sub "${ServiceName}-${Env}-cluster-endpoint"

  OIDCProviderArn:
    Value: !Ref OIDCProvider
    Export:
      Name: !Sub "${ServiceName}-${Env}-oidc-provider-arn"

  KarpenterNodeRoleArn:
    Value: !GetAtt KarpenterNodeRole.Arn
    Export:
      Name: !Sub "${ServiceName}-${Env}-karpenter-node-role-arn"

  KarpenterNodeInstanceProfileName:
    Value: !Ref KarpenterNodeInstanceProfile
    Export:
      Name: !Sub "${ServiceName}-${Env}-karpenter-node-instance-profile"

  AppServiceAccountRoleArn:
    Value: !GetAtt AppServiceAccountRole.Arn
    Export:
      Name: !Sub "${ServiceName}-${Env}-app-sa-role-arn"

  ALBControllerRoleArn:
    Value: !GetAtt ALBControllerRole.Arn
    Export:
      Name: !Sub "${ServiceName}-${Env}-alb-controller-role-arn"
```

---

### A-3. app-stack.yaml

```yaml
AWSTemplateFormatVersion: "2010-09-09"
Description: "myapp application stack - ECR, Secrets Manager, CloudWatch, SNS, S3"

Parameters:
  Env:
    Type: String
    AllowedValues: [prod, stg]
  ServiceName:
    Type: String
    Default: myapp
  AlertEmail:
    Type: String
    Description: "アラート通知先メールアドレス"
    Default: "ops-team@example.com"

Resources:
  # ─────────────────────────────
  # ECR
  # ─────────────────────────────
  ECRRepository:
    Type: AWS::ECR::Repository
    Properties:
      RepositoryName: !Sub "${ServiceName}-${Env}"
      ImageScanningConfiguration:
        ScanOnPush: true
      LifecyclePolicy:
        LifecyclePolicyText: |
          {
            "rules": [
              {
                "rulePriority": 1,
                "description": "最新10世代のみ保持",
                "selection": {
                  "tagStatus": "any",
                  "countType": "imageCountMoreThan",
                  "countNumber": 10
                },
                "action": { "type": "expire" }
              }
            ]
          }

  # ─────────────────────────────
  # Secrets Manager
  # ─────────────────────────────
  DBSecret:
    Type: AWS::SecretsManager::Secret
    Properties:
      Name: !Sub "${ServiceName}/${Env}/db"
      Description: "DB接続情報"
      SecretString: !Sub |
        {
          "host": "REPLACE_ME",
          "port": "5432",
          "username": "REPLACE_ME",
          "password": "REPLACE_ME",
          "dbname": "${ServiceName}"
        }

  RedisSecret:
    Type: AWS::SecretsManager::Secret
    Properties:
      Name: !Sub "${ServiceName}/${Env}/redis"
      Description: "Redis接続情報"
      SecretString: |
        {
          "host": "REPLACE_ME",
          "port": "6379"
        }

  APIKeySecret:
    Type: AWS::SecretsManager::Secret
    Properties:
      Name: !Sub "${ServiceName}/${Env}/api-keys"
      Description: "外部APIキー"
      SecretString: |
        {
          "API_KEY_1": "REPLACE_ME"
        }

  # ─────────────────────────────
  # CloudWatch Log Groups
  # ─────────────────────────────
  ControlPlaneLogGroup:
    Type: AWS::Logs::LogGroup
    Properties:
      LogGroupName: !Sub "/aws/eks/${ServiceName}-${Env}-eks-cluster/cluster"
      RetentionInDays: 90

  AppLogGroup:
    Type: AWS::Logs::LogGroup
    Properties:
      LogGroupName: !Sub "/${ServiceName}/${Env}/application"
      RetentionInDays: 30

  # ─────────────────────────────
  # S3（ALBアクセスログ）
  # ─────────────────────────────
  ALBLogBucket:
    Type: AWS::S3::Bucket
    Properties:
      BucketName: !Sub "${ServiceName}-${Env}-alb-logs-${AWS::AccountId}"
      LifecycleConfiguration:
        Rules:
          - Id: DeleteAfter30Days
            Status: Enabled
            ExpirationInDays: 30
      PublicAccessBlockConfiguration:
        BlockPublicAcls: true
        BlockPublicPolicy: true
        IgnorePublicAcls: true
        RestrictPublicBuckets: true

  ALBLogBucketPolicy:
    Type: AWS::S3::BucketPolicy
    Properties:
      Bucket: !Ref ALBLogBucket
      PolicyDocument:
        Version: "2012-10-17"
        Statement:
          - Effect: Allow
            Principal:
              AWS: "arn:aws:iam::582318560864:root"  # ap-northeast-1のELBサービスアカウント
            Action: s3:PutObject
            Resource: !Sub "${ALBLogBucket.Arn}/AWSLogs/${AWS::AccountId}/*"

  # ─────────────────────────────
  # SNS（アラート通知）
  # ─────────────────────────────
  AlertTopic:
    Type: AWS::SNS::Topic
    Properties:
      TopicName: !Sub "${ServiceName}-${Env}-alerts"
      Subscription:
        - Protocol: email
          Endpoint: !Ref AlertEmail

  # ─────────────────────────────
  # CloudWatch Alarms
  # ─────────────────────────────
  CPUAlarm:
    Type: AWS::CloudWatch::Alarm
    Properties:
      AlarmName: !Sub "${ServiceName}-${Env}-cpu-high"
      AlarmDescription: "Pod平均CPU使用率が80%を5分間超過"
      MetricName: pod_cpu_utilization
      Namespace: ContainerInsights
      Dimensions:
        - Name: ClusterName
          Value: !Sub "${ServiceName}-${Env}-eks-cluster"
        - Name: Namespace
          Value: !Ref ServiceName
      Statistic: Average
      Period: 60
      EvaluationPeriods: 5
      Threshold: 80
      ComparisonOperator: GreaterThanThreshold
      TreatMissingData: notBreaching
      AlarmActions:
        - !Ref AlertTopic

  MemoryAlarm:
    Type: AWS::CloudWatch::Alarm
    Properties:
      AlarmName: !Sub "${ServiceName}-${Env}-memory-high"
      AlarmDescription: "Pod平均メモリ使用率が85%を5分間超過"
      MetricName: pod_memory_utilization
      Namespace: ContainerInsights
      Dimensions:
        - Name: ClusterName
          Value: !Sub "${ServiceName}-${Env}-eks-cluster"
        - Name: Namespace
          Value: !Ref ServiceName
      Statistic: Average
      Period: 60
      EvaluationPeriods: 5
      Threshold: 85
      ComparisonOperator: GreaterThanThreshold
      TreatMissingData: notBreaching
      AlarmActions:
        - !Ref AlertTopic

  Error5xxAlarm:
    Type: AWS::CloudWatch::Alarm
    Properties:
      AlarmName: !Sub "${ServiceName}-${Env}-5xx-rate"
      AlarmDescription: "ALB 5xxエラー率が1%を3分間超過"
      Metrics:
        - Id: errors
          MetricStat:
            Metric:
              Namespace: AWS/ApplicationELB
              MetricName: HTTPCode_Target_5XX_Count
            Period: 60
            Stat: Sum
        - Id: total
          MetricStat:
            Metric:
              Namespace: AWS/ApplicationELB
              MetricName: RequestCount
            Period: 60
            Stat: Sum
        - Id: rate
          Expression: "errors / total * 100"
          Label: "5xx Error Rate"
      ComparisonOperator: GreaterThanThreshold
      EvaluationPeriods: 3
      Threshold: 1
      TreatMissingData: notBreaching
      AlarmActions:
        - !Ref AlertTopic

Outputs:
  ECRRepositoryUri:
    Value: !GetAtt ECRRepository.RepositoryUri
    Export:
      Name: !Sub "${ServiceName}-${Env}-ecr-uri"

  DBSecretArn:
    Value: !Ref DBSecret
    Export:
      Name: !Sub "${ServiceName}-${Env}-db-secret-arn"

  AlertTopicArn:
    Value: !Ref AlertTopic
    Export:
      Name: !Sub "${ServiceName}-${Env}-alert-topic-arn"
```

---

## 付録B: K8sマニフェスト完全版

### ディレクトリ構成

```
k8s/
├── namespace.yaml
├── serviceaccount.yaml
├── aws-auth-patch.yaml
├── cluster-secret-store.yaml
├── external-secret.yaml
├── deployment.yaml
├── service.yaml
├── ingress.yaml
├── hpa.yaml
├── pdb.yaml
├── karpenter-nodepool.yaml
└── karpenter-ec2nodeclass.yaml
```

### k8s/namespace.yaml

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: myapp
```

### k8s/serviceaccount.yaml

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: myapp-sa
  namespace: myapp
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::XXXXXXXXXXXX:role/myapp-prod-app-role
```

### k8s/cluster-secret-store.yaml

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: aws-secrets-manager
spec:
  provider:
    aws:
      service: SecretsManager
      region: ap-northeast-1
      auth:
        jwt:
          serviceAccountRef:
            name: myapp-sa
            namespace: myapp
```

### k8s/external-secret.yaml

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: myapp-secret
  namespace: myapp
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: aws-secrets-manager
    kind: ClusterSecretStore
  target:
    name: myapp-secret
    creationPolicy: Owner
  data:
    - secretKey: DB_HOST
      remoteRef:
        key: myapp/prod/db
        property: host
    - secretKey: DB_PORT
      remoteRef:
        key: myapp/prod/db
        property: port
    - secretKey: DB_USER
      remoteRef:
        key: myapp/prod/db
        property: username
    - secretKey: DB_PASSWORD
      remoteRef:
        key: myapp/prod/db
        property: password
    - secretKey: REDIS_HOST
      remoteRef:
        key: myapp/prod/redis
        property: host
    - secretKey: REDIS_PORT
      remoteRef:
        key: myapp/prod/redis
        property: port
    - secretKey: API_KEY_1
      remoteRef:
        key: myapp/prod/api-keys
        property: API_KEY_1
```

### k8s/deployment.yaml

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
  namespace: myapp
  labels:
    app: myapp
spec:
  replicas: 2
  selector:
    matchLabels:
      app: myapp
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
  template:
    metadata:
      labels:
        app: myapp
    spec:
      serviceAccountName: myapp-sa
      topologySpreadConstraints:
        - maxSkew: 1
          topologyKey: topology.kubernetes.io/zone
          whenUnsatisfiable: DoNotSchedule
          labelSelector:
            matchLabels:
              app: myapp
      containers:
        - name: myapp
          image: XXXXXXXXXXXX.dkr.ecr.ap-northeast-1.amazonaws.com/myapp-prod:latest
          imagePullPolicy: Always
          ports:
            - name: http
              containerPort: 8080
              protocol: TCP
          resources:
            requests:
              cpu: 250m
              memory: 256Mi
            limits:
              cpu: 500m
              memory: 512Mi
          env:
            - name: DB_HOST
              valueFrom:
                secretKeyRef:
                  name: myapp-secret
                  key: DB_HOST
            - name: DB_PORT
              valueFrom:
                secretKeyRef:
                  name: myapp-secret
                  key: DB_PORT
            - name: DB_USER
              valueFrom:
                secretKeyRef:
                  name: myapp-secret
                  key: DB_USER
            - name: DB_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: myapp-secret
                  key: DB_PASSWORD
            - name: REDIS_HOST
              valueFrom:
                secretKeyRef:
                  name: myapp-secret
                  key: REDIS_HOST
            - name: REDIS_PORT
              valueFrom:
                secretKeyRef:
                  name: myapp-secret
                  key: REDIS_PORT
          readinessProbe:
            httpGet:
              path: /healthz
              port: 8080
            initialDelaySeconds: 10
            periodSeconds: 5
            failureThreshold: 3
          livenessProbe:
            httpGet:
              path: /healthz
              port: 8080
            initialDelaySeconds: 15
            periodSeconds: 10
            failureThreshold: 3
      terminationGracePeriodSeconds: 30
```

### k8s/service.yaml

```yaml
apiVersion: v1
kind: Service
metadata:
  name: myapp
  namespace: myapp
  labels:
    app: myapp
spec:
  selector:
    app: myapp
  ports:
    - name: http
      port: 80
      targetPort: 8080
      protocol: TCP
  type: ClusterIP
```

### k8s/ingress.yaml

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: myapp
  namespace: myapp
  annotations:
    kubernetes.io/ingress.class: alb
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:ap-northeast-1:XXXXXXXXXXXX:certificate/XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTPS":443}]'
    alb.ingress.kubernetes.io/ssl-redirect: "443"
    alb.ingress.kubernetes.io/security-groups: sg-XXXXXXXXXXXXXXXXX
    alb.ingress.kubernetes.io/load-balancer-attributes: access_logs.s3.enabled=true,access_logs.s3.bucket=myapp-prod-alb-logs-XXXXXXXXXXXX
    alb.ingress.kubernetes.io/healthcheck-path: /healthz
    alb.ingress.kubernetes.io/healthcheck-interval-seconds: "15"
spec:
  rules:
    - host: myapp.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: myapp
                port:
                  number: 80
```

### k8s/hpa.yaml

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: myapp-hpa
  namespace: myapp
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: myapp
  minReplicas: 2
  maxReplicas: 10
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 60
    - type: Resource
      resource:
        name: memory
        target:
          type: Utilization
          averageUtilization: 70
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 300
      policies:
        - type: Pods
          value: 1
          periodSeconds: 60
    scaleUp:
      stabilizationWindowSeconds: 0
      policies:
        - type: Pods
          value: 2
          periodSeconds: 30
```

### k8s/pdb.yaml

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: myapp-pdb
  namespace: myapp
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app: myapp
```

### k8s/karpenter-nodepool.yaml

```yaml
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: default
spec:
  template:
    metadata:
      labels:
        role: app
    spec:
      requirements:
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["spot", "on-demand"]
        - key: node.kubernetes.io/instance-category
          operator: In
          values: ["c", "m", "r"]
        - key: node.kubernetes.io/instance-generation
          operator: Gt
          values: ["4"]
        - key: kubernetes.io/arch
          operator: In
          values: ["amd64"]
      nodeClassRef:
        group: karpenter.k8s.aws
        kind: EC2NodeClass
        name: default
      expireAfter: 720h  # 30日でノードを強制更新（OSパッチ適用）
  limits:
    cpu: "100"
    memory: 400Gi
  disruption:
    consolidationPolicy: WhenEmptyOrUnderutilized
    consolidateAfter: 30s
```

### k8s/karpenter-ec2nodeclass.yaml

```yaml
apiVersion: karpenter.k8s.aws/v1
kind: EC2NodeClass
metadata:
  name: default
spec:
  amiSelectorTerms:
    - alias: al2023@latest
  subnetSelectorTerms:
    - tags:
        karpenter.sh/discovery: myapp-prod-eks-cluster
  securityGroupSelectorTerms:
    - tags:
        karpenter.sh/discovery: myapp-prod-eks-cluster
  role: myapp-prod-karpenter-node-role
  blockDeviceMappings:
    - deviceName: /dev/xvda
      ebs:
        volumeSize: 50Gi
        volumeType: gp3
        deleteOnTermination: true
  tags:
    Environment: prod
    Service: myapp
```

---

## 付録C: 作業チェックリスト

実装時にこのリストを上から順に消化する。

### Phase 1: AWS基盤構築

- [ ] AWS CLIプロファイルの確認（`aws sts get-caller-identity`）
- [ ] network-stackのデプロイ完了
- [ ] eks-stackのデプロイ完了（CAPABILITY_NAMED_IAM 指定を忘れずに）
- [ ] app-stackのデプロイ完了
- [ ] kubeconfigの更新（`aws eks update-kubeconfig`）
- [ ] ノードのReady確認（`kubectl get nodes`）

### Phase 2: K8s基盤セットアップ

- [ ] aws-authのパッチ適用
- [ ] AWS Load Balancer ControllerのHelm install
- [ ] External Secrets OperatorのHelm install
- [ ] Karpenter NodePool / EC2NodeClassの適用
- [ ] 各コンポーネントのRunning確認

### Phase 3: アプリケーションデプロイ

- [ ] ECRへのイメージPush
- [ ] Namespace作成
- [ ] ServiceAccount作成
- [ ] ClusterSecretStore作成
- [ ] ExternalSecret作成・同期確認（`kubectl get externalsecret`）
- [ ] Deployment / Service / Ingress適用
- [ ] HPA / PDB適用

### Phase 4: 動作確認

- [ ] Pod起動確認（`kubectl get pods -n myapp`）
- [ ] ヘルスチェック疎通確認
- [ ] HTTPS経由の疎通確認（`curl https://myapp.example.com/healthz`）
- [ ] CloudWatchにメトリクス・ログが届いていること
- [ ] HPAの動作確認（負荷テスト）
- [ ] Karpenterのスケールアウト確認
- [ ] 受け入れ基準チェックリスト（セクション9-4）の全項目完了

### Phase 5: Secrets Managerの値更新

- [ ] `myapp/prod/db`の`REPLACE_ME`を実際の値に更新
- [ ] `myapp/prod/redis`の`REPLACE_ME`を実際の値に更新
- [ ] `myapp/prod/api-keys`の`REPLACE_ME`を実際の値に更新
- [ ] ExternalSecretの再同期確認

---

*本仕様書のすべての設定値・確定値はTBDなしで記載済みであること。実装時に変更が生じた場合は本文書を更新すること。*
