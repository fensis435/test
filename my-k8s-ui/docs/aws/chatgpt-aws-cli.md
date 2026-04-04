（EKS + CFn + CLI 前提）

---

# 🎯 AWS CLI & EKS構築チートシート（実務版）

---

# 🧠 ① AWS CLIの基本構造

```bash
aws <service> <operation>
```

---

## よく使う操作パターン

| 操作       | 例                | 意味          |
| -------- | ---------------- | ----------- |
| list     | list-clusters    | 一覧（軽量）      |
| describe | describe-subnets | 詳細          |
| get      | get-role         | 単体取得（IAMなど） |
| create   | create-stack     | 作成          |
| delete   | delete-vpc       | 削除          |

---

## 出力制御

```bash
--output json
--output yaml
--output table
```

---

## フィルタ・整形

```bash
--filters Name=xxx,Values=yyy
--query '式'
```

---

# 🧱 ② よく使うCLIコマンド一覧

---

## 🌐 VPC / Subnet

```bash
aws ec2 describe-vpcs

aws ec2 describe-subnets \
  --filters Name=vpc-id,Values=vpc-xxxx \
  --output table
```

---

## 🔐 IAM

```bash
aws iam list-roles

aws iam get-role \
  --role-name MyRole
```

---

## ☸️ EKS

```bash
aws eks list-clusters

aws eks describe-cluster \
  --name my-eks

aws eks list-nodegroups \
  --cluster-name my-eks

aws eks describe-nodegroup \
  --cluster-name my-eks \
  --nodegroup-name ng-1
```

---

## 🖥 EC2（Node実体）

```bash
aws ec2 describe-instances
```

---

## 🌐 ALB

```bash
aws elbv2 describe-load-balancers
```

---

## 📦 CloudFormation

```bash
aws cloudformation describe-stacks

aws cloudformation list-stack-resources \
  --stack-name my-eks

aws cloudformation describe-stack-events \
  --stack-name my-eks
```

---

# 🚀 ③ CloudFormation運用フロー

---

## 作成 / 更新（実務はこれ一択）

```bash
aws cloudformation deploy \
  --stack-name my-eks \
  --template-file template.yaml \
  --parameters file://params.json \
  --capabilities CAPABILITY_NAMED_IAM
```

---

## 削除

```bash
aws cloudformation delete-stack \
  --stack-name my-eks
```

---

## 待機（重要）

```bash
aws cloudformation wait stack-create-complete
aws cloudformation wait stack-update-complete
```

---

## トラブル確認

```bash
aws cloudformation describe-stack-events
```

---

# 📄 ④ Parameter管理

---

## params.json

```json
[
  { "ParameterKey": "VpcId", "ParameterValue": "vpc-xxxx" },
  { "ParameterKey": "PrivateSubnet1", "ParameterValue": "subnet-yyyy" }
]
```

---

## YAML運用（推奨）

```yaml
VpcId: vpc-xxxx
PrivateSubnet1: subnet-yyyy
```

→ `yq` でJSON変換

---

# ☸️ ⑤ EKS構成（今回の前提）

---

## ノード構成

```text
管理系ノード（常駐） → Managed Node Group
計算系ノード（動的） → Karpenter
```

---

## 必須IAM

---

### Cluster Role

* AmazonEKSClusterPolicy

---

### Node Role

* AmazonEKSWorkerNodePolicy
* AmazonEC2ContainerRegistryReadOnly
* AmazonEKS_CNI_Policy

---

## Pod確認

```bash
kubectl get pods
```

---

# 🌐 ⑥ ALB（internal / public）

---

## internal（今回）

* VPC内のみアクセス可能
* パブリックアクセス不可

---

## public

* インターネット公開

---

# 🌍 ⑦ DNS設計

---

## 👉 Amazon Route 53

---

## Private Hosted Zone

```text
dev.internal.example.com
```

---

## 特徴

| 項目     | 内容     |
| ------ | ------ |
| 解決範囲   | VPC内のみ |
| ローカルPC | ❌ 解決不可 |
| VPN    | ⭕      |

---

## SSM開発時

```text
localhost:8080 → ALB
```

---

## ドメイン確認

```text
hostsに定義
127.0.0.1 dev.internal.example.com
```

---

# 🔐 ⑧ SSMポートフォワード

---

```bash
aws ssm start-session \
  --target i-xxxx \
  --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters '{"host":["internal-alb"],"portNumber":["80"],"localPortNumber":["8080"]}'
```

---

# ⚠️ ⑨ 削除と依存関係

---

## AWSの特徴

```text
finalizerなし
→ 依存関係でブロック
```

---

## よくある原因

* ENI残存
* Security Group参照
* Subnet未削除

---

## 対処

```bash
aws ec2 describe-network-interfaces
```

---

👉 依存元を特定して削除

---

# 🔍 ⑩ 依存関係の追い方

---

## ❌ ツリー表示

→ ない

---

## ✅ 方法

1. エラーを見る
2. describeで確認
3. ENI起点で辿る
4. タグで検索

---

---

# 🧠 ⑪ 重要思想（ここが一番大事）

---

## AWS

```text
サービス単位で分断
```

---

## Kubernetes

```text
リソース統合管理
```

---

👉 違い

|      | AWS    | K8s       |
| ---- | ------ | --------- |
| 管理単位 | サービス   | API       |
| 依存   | 手動     | 自動        |
| 削除   | 依存解除必要 | finalizer |

---

# 🚀 ⑫ 推奨開発フロー

---

## Step 1

* IAM
* EKS
* NodeGroup

---

## Step 2

* Pod起動確認

---

## Step 3

* Karpenter

---

## Step 4

* ALB / Ingress

---

## Step 5

* DNS / ドメイン

---

# 🎯 最終まとめ

---

## CLI

* `aws <service> <operation>`
* describe / list / get を使い分け

---

## CFn

* deployで統一
* paramsファイル管理

---

## EKS

* 管理系ノード固定
* 計算系はKarpenter

---

## ネットワーク

* private ALB + SSM

---

## DNS

* Private Hosted Zone
* ローカルはhostsで補完

---

## 削除

* 依存関係を手で解決

---

---
