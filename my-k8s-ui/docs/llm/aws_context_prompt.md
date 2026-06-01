そのケースこそ「安いモデルで知識ベース化 → 高性能モデルで設計・変換」が効果を発揮します。

ただし、アプリケーションコードとは少し違って、

> 「何のリソースが作られているか」

よりも

> 「どの順番で、どの依存関係で、何のために構築されているか」

を抽出するのが重要になります。

---

# あなたのケース

現状イメージ

```text
構築手順書
↓
手順 1
PowerShell

手順 2
CloudFormation

手順 3
AWS CLI

手順 4
JSON

手順 5
XML

手順 6
手動設定

...

手順 50
```

成果物

```text
CFN Template 1
CFN Template 2
CFN Template 3

parameters-dev.json
parameters-stg.json
parameters-prod.json

デプロイ手順
5ステップ以内
```

---

# まずやるべきこと

いきなり

> 全部CFN化して

は危険。

先にAIに

**構築知識ベース**

を作らせる。

---

# 1. AWS_CONTEXT.md

最初に作る。

プロンプト例

```text
このAWS構築資産一式を分析してください。

以下を対象とします。

- CloudFormation
- PowerShell
- AWS CLI
- JSON
- XML
- 手順書

目的はCFN統合です。

まずコード変換は行わず、
構築知識ベースを作成してください。

出力形式:

# Infrastructure Overview

# AWS Services

# Resource Inventory

# Dependency Graph

# Deployment Order

# Manual Operations

# External Dependencies

# Environment Differences

# Migration Risks
```

---

# 2. RESOURCE_INVENTORY.md

これが超重要。

```text
全資産からAWSリソース一覧を作成してください。

出力形式:

Resource:
Type:
Created By:
Depends On:
Environment:
Configuration Source:
```

例

```text
VPC
Type: AWS::EC2::VPC

Created By:
network.ps1

Depends On:
なし

Environment:
All
```

---

# 3. DEPLOYMENT_FLOW.md

CFN化で最も重要。

```text
構築順序を抽出してください。

出力形式:

Step 1
VPC

Step 2
Subnets

Step 3
Route Tables

Step 4
Security Groups

Step 5
IAM Roles

...

各ステップについて

- なぜ必要か
- 前提条件
- 後続依存
```

---

# 4. MANUAL_OPERATIONS.md

意外と見落とす。

```text
手動作業を抽出してください。

出力形式:

作業名:

対象サービス:

理由:

CFN化可能か:

代替手段:
```

---

例えば

```text
Route53レコード追加

手動

↓
実はCFN可能
```

みたいな発見がある。

---

# 5. CFN_MIGRATION_PLAN.md

ここから変換。

```text
この構築資産を
CloudFormation中心へ移行してください。

出力形式:

Phase 1

CFN化対象

Phase 2

CLI削除

Phase 3

手動作業排除

Phase 4

統合
```

---

# AIにやらせるべき分析

かなり重要。

```text
以下を分類してください。

Category A:
CloudFormationで実現可能

Category B:
Custom Resourceで実現可能

Category C:
Lambda-backed Custom Resourceが必要

Category D:
CFNでは困難

Category E:
運用手順として残すべき
```

---

# 最終的な目標構造

私ならこうする。

```text
infra/

├─ network.yaml
├─ security.yaml
├─ application.yaml

├─ params/
│
├─ dev.json
├─ stg.json
└─ prod.json

├─ deploy.ps1

└─ README.md
```

---

# AIに最後にやらせるプロンプト

知識ベース完成後。

```text
AWS_CONTEXT.md
RESOURCE_INVENTORY.md
DEPLOYMENT_FLOW.md
MANUAL_OPERATIONS.md

を参照してください。

目的:

現在50ステップ以上ある構築手順を

CloudFormationテンプレート数個
+
環境別パラメータ
+
デプロイスクリプト1本

へ統合したい。

以下を提案してください。

1. スタック分割案
2. Nested Stack案
3. Parameter設計
4. Export/Import設計
5. Custom Resource候補
6. 削除可能なCLI処理
7. 削除可能な手動作業
8. 推奨ディレクトリ構成
9. 移行順序
10. 移行リスク
```

---

実務的には、あなたのケースでは **「まずCFNを書く」のではなく、「AWS環境の構築知識をドキュメント化する」** のが先です。

PowerShell、AWS CLI、JSON、XML、手順書が混在している環境では、コード量そのものよりも「暗黙の依存関係」が最大の敵です。上で挙げた `AWS_CONTEXT.md`、`RESOURCE_INVENTORY.md`、`DEPLOYMENT_FLOW.md`、`MANUAL_OPERATIONS.md` を先に作り、その知識ベースを高性能モデルに渡してから CFN 化を進めると、大量のスクリプトを毎回読み込ませる必要がなくなり、設計の抜け漏れもかなり減らせます。
