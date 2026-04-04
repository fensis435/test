---

# 🎯 全体像（最終アーキテクチャ）

```text
[ユーザPC]
   ↓ (SSM PortForward or VPN)
[踏み台EC2（private）]
   ↓
[internal ALB]
   ↓
[nginx-ingress（EKS）]
   ↓
[envoy（各workspace）]
   ↓
[workspace Web App]
```

---

# 🧠 コンセプト

---

## ❗インターネット完全遮断

* ALB → internal
* サブネット → privateのみ
* IGW不要（※場合による）
* NAT最小化 or なし

---

## ❗アクセス経路は2つだけ

---

### ① 開発

```text
ローカル → SSM → ALB
```

---

### ② 本番（企業内）

```text
社内NW → VPN/DirectConnect → ALB
```

---

# 🧱 コンポーネント詳細

---

# ① VPC構成

---

## サブネット

```text
Private Subnet A/B
  - EKS Node
  - ALB
  - EC2踏み台
```

---

## ❗重要

👉 **public subnetは使わない（または未使用）**

---

---

# ② EKS

---

👉 Amazon EKS

---

## 構成

* Managed Node Group（管理系）
* Karpenter（計算系）
* Pod Identity

---

## エンドポイント

```text
Private Endpoint ONLY
```

---

👉 kubectlもSSM経由

---

---

# ③ ALB（internal）

---

👉 AWS Application Load Balancer

---

## 設定

```text
scheme: internal
subnet: private
```

---

## 役割

```text
L7入口（唯一の入口）
```

---

---

# ④ nginx-ingress（1段目）

---

## 役割

👉 **URL書き換え（workspace ID除去）**

---

### 例

```text
/access/ws-123/app → /app
```

---

## なぜ必要か

* ALBだけでは複雑なrewrite無理
* regex処理必要

---

---

# ⑤ envoy（2段目）

---

## 役割

* workspaceごとのrouting
* service mesh的役割

---

## 構造

```text
namespace = tenant
envoy per workspace
```

---

---

# ⑥ DNS（完全private）

---

👉 Amazon Route 53

---

## Private Hosted Zone

```text
*.dev.internal.example.com
```

---

## 例

```text
ws-123.dev.internal.example.com
```

---

---

# ⑦ 認証・アクセス制御

---

## RBAC（アプリ側）

* GUIログイン
* workspaceごと権限制御

---

## AWS側

* SGで制限
* ALBは社内IPのみ許可（本番）

---

---

# ⑧ アクセスパターン

---

## 開発

```text
localhost:8080 → SSM → ALB
```

---

## 本番

```text
browser → VPN → ALB
```

---

---

# 🔐 セキュリティ設計

---

## SG

```text
ALB:
  inbound: 踏み台 or VPNのみ

EKS Node:
  inbound: ALBのみ
```

---

---

# 💡 重要な設計判断

---

# ❗① NAT Gatewayどうする？

---

## パターン

### ✔ 最小構成

* NATあり（イメージPull用）

---

### ✔ 完全閉域

* VPC Endpoint使用

---

## 必要なEndpoint

* ECR
* S3
* STS

---

---

# ❗② ALBを唯一の入口にする

---

👉 これが最重要

---

```text
直接Podにアクセス禁止
```

---

---

# ❗③ namespace = tenant

---

👉 あなたの設計と一致

---

---

# 🚀 Kubernetes側構成

---

## Ingress（nginx）

```yaml
path: /ws-123/(.*)
rewrite: /$1
```

---

## envoy

* Service単位で配置
* workspace isolation

---

---

# 🔁 運用フロー（最終）

---

## 起動

1. EKS起動
2. Karpenter
3. nginx ingress
4. envoy
5. ALB
6. DNS

---

---

## 終了

```text
Ingress削除
→ ALB削除
→ DNS削除
→ Karpenter削除
→ EKS削除
```

---

---

# 🎯 完成形の特徴

---

## ✔ 完全private

* 外部から見えない
* 攻撃面最小

---

## ✔ オンプレ構成と一致

* reverse proxy 2段
* namespace tenant

---

## ✔ 拡張性

* workspace増加対応
* auto scaling

---

---

# 🧠 あなたの設計の評価

正直に言うと👇

👉 **かなり正しい方向**

---

特に良い点：

* reverse proxy分離（nginx + envoy）
* tenant isolation
* private前提

---

---

# ⚠️ 改善ポイント（プロ視点）

---

## ❗① Hostベース routingも検討

```text
ws-123.example.com
```

👉 URLよりシンプル

---

## ❗② envoyの責務を絞る

👉 L7全部やらせない

---

## ❗③ ALBログ必須

---

---

# 🎯 最終まとめ

---

## 完全private構成

```text
SSM/VPN → internal ALB → nginx → envoy → app
```

---

## AWS要素

* EKS
* ALB（internal）
* Route53（private）
* Pod Identity

---

---

# 💬 次にやるべきこと

---

ここまで来たら👇

👉 **設計から実装フェーズへ**

---
