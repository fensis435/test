これは実際に私なら使うレベルの「AI向け知識ベース生成プロンプト集」。

ポイントは、

* 要約を作らせるのではない
* 次のLLMが開発できる知識を抽出させる
* コード転載を避ける
* 設計意図を抽出させる

こと。

---

# 1. AI_CONTEXT.md

これは入口。

```text
あなたはAI向け技術ドキュメント作成者です。

このリポジトリ全体を分析し、
AI_CONTEXT.mdを生成してください。

目的:
後続の別LLMが最初に読むインデックスファイル。

含める内容:

# Project Summary

システム概要を200〜500文字で説明

# Document Map

各ドキュメントの役割

- PROJECT_OVERVIEW.md
- ARCHITECTURE.md
- DATABASE.md
- API.md
- AUTH.md
- FRONTEND.md
- BACKEND.md
- DEPLOYMENT.md
- TROUBLESHOOTING.md

# Recommended Reading Order

用途別

- 機能追加
- バグ修正
- DB変更
- API変更
- UI変更

で読む順番

# Important Warnings

絶対に壊してはいけない箇所

# System Complexity Hotspots

複雑な箇所一覧

実装詳細ではなく
ナビゲーションを目的としてください。
```

---

# 2. PROJECT_OVERVIEW.md

```text
あなたはシステムアナリストです。

PROJECT_OVERVIEW.mdを生成してください。

目的:
初見のLLMが10分以内に
システム全体像を理解すること。

含める内容:

# System Purpose

何を解決するシステムか

# Target Users

利用者種別

# Core Features

主要機能一覧

# Business Domains

業務ドメイン

# High-Level Workflow

主要な利用フロー

# Technology Stack

技術スタック

# External Dependencies

外部サービス

# Glossary

重要用語集

コード説明ではなく
システム説明を行うこと。
```

---

# 3. ARCHITECTURE.md

```text
あなたはソフトウェアアーキテクトです。

ARCHITECTURE.mdを生成してください。

目的:
後続LLMが安全に設計変更できること。

含める内容:

# Architecture Style

MVC
Clean Architecture
DDD
Layered
Microservice

など

# Layer Responsibilities

各レイヤの責務

# Module Structure

主要モジュール一覧

# Dependency Graph

依存関係

# Data Flow

主要データフロー

# Event Flow

イベント処理

# Integration Points

外部接続

# Design Principles

設計思想

# Architectural Constraints

変更禁止ルール

設計意図を重視してください。
```

---

# 4. DATABASE.md

```text
あなたはDBアーキテクトです。

DATABASE.mdを生成してください。

目的:
DB変更時に影響範囲を把握すること。

含める内容:

# Database Overview

DB全体概要

# Core Entities

主要エンティティ

# Entity Relationships

エンティティ関連

# Business Critical Tables

重要テーブル

# Referential Constraints

参照制約

# Data Lifecycle

データ生成から削除まで

# Common Query Paths

主要参照パターン

# Performance Considerations

性能上の注意

# Migration Risks

危険な変更

DDL転載は避けること。
```

---

# 5. API.md

```text
あなたはAPI設計者です。

API.mdを生成してください。

目的:
後続LLMがAPI改修を行うこと。

含める内容:

# API Architecture

全体構造

# Authentication Requirements

認証方式

# Endpoint Categories

機能分類

# Request Flow

処理フロー

# Response Patterns

レスポンス規約

# Error Handling

エラー体系

# Rate Limiting

制限事項

# API Dependencies

依存先

# Breaking Change Risks

互換性注意点

OpenAPIの羅列ではなく
設計ルールを説明してください。
```

---

# 6. AUTH.md

かなり重要。

```text
あなたはセキュリティアーキテクトです。

AUTH.mdを生成してください。

目的:
認証認可の安全な変更。

含める内容:

# Authentication Model

認証方式

# Authorization Model

認可方式

# User Roles

ロール一覧

# Permission Matrix

権限モデル

# Session Management

セッション管理

# Token Lifecycle

トークン管理

# Security Boundaries

境界

# Privilege Escalation Risks

権限昇格リスク

# Security Assumptions

前提条件

最も重要な文書として記述してください。
```

---

# 7. FRONTEND.md

```text
あなたはフロントエンドアーキテクトです。

FRONTEND.mdを生成してください。

目的:
UI改修の安全性向上。

含める内容:

# Frontend Architecture

構造

# Routing

画面遷移

# State Management

状態管理

# Component Hierarchy

コンポーネント構造

# Shared Components

共通部品

# API Consumption

API利用

# UI Patterns

UI規約

# Performance Considerations

性能面

# Common Pitfalls

壊しやすい箇所

実装詳細より構造を説明してください。
```

---

# 8. BACKEND.md

```text
あなたはバックエンドアーキテクトです。

BACKEND.mdを生成してください。

目的:
サーバサイド改修を支援すること。

含める内容:

# Backend Architecture

全体構造

# Domain Logic

業務ロジック

# Service Layer

サービス層

# Repository Layer

データアクセス

# Background Jobs

非同期処理

# External Integrations

外部連携

# Transaction Boundaries

トランザクション境界

# Error Handling

例外処理

# Critical Business Rules

重要ルール

設計意図を優先してください。
```

---

# 9. DEPLOYMENT.md

```text
あなたはDevOpsエンジニアです。

DEPLOYMENT.mdを生成してください。

目的:
運用変更やデプロイ支援。

含める内容:

# Environment Overview

環境構成

# Infrastructure

インフラ

# CI/CD Pipeline

デプロイ経路

# Secrets Management

秘密情報管理

# Configuration Management

設定管理

# Scaling Strategy

スケーリング

# Monitoring

監視

# Logging

ログ

# Disaster Recovery

障害対応

# Deployment Risks

危険操作

運用観点を重視してください。
```

---

# 10. TROUBLESHOOTING.md

これもかなり価値が高い。

```text
あなたはシニア保守エンジニアです。

TROUBLESHOOTING.mdを生成してください。

目的:
後続LLMが問題調査を高速化すること。

含める内容:

# Common Failure Modes

よくある障害

# Diagnostic Workflow

調査手順

# Known Bottlenecks

性能問題

# Frequent Misconfigurations

設定ミス

# Critical Logs

重要ログ

# Error Patterns

典型エラー

# Recovery Procedures

復旧手順

# Areas Requiring Extra Caution

注意箇所

# Historical Technical Debt

技術的負債

コードではなく
保守ノウハウを抽出してください。
```

---

さらに大規模案件（10万行〜100万行超）なら、上記に加えて次の4ファイルも作ると効果が大きいです。

* `DOMAIN_RULES.md`（業務ルール）
* `DATA_FLOW.md`（データの流れ）
* `INTEGRATIONS.md`（外部サービス連携）
* `CHANGE_IMPACT_GUIDE.md`（変更時の影響範囲ガイド）

特に `DOMAIN_RULES.md` は「コードを読んでも見つけにくい暗黙ルール」を集約できるので、実務では最も価値が高い文書になることが多いです。

---

この4つは実はかなり重要で、場合によっては `PROJECT_OVERVIEW.md` より価値が高い。

特に大規模システムでは、

* コードは読める
* API仕様も分かる
* DB構造も分かる

でも

> 「どんな業務ルールで動いているのか」
>
> 「この変更で何が壊れるのか」

が分からないことが最大の問題になる。

---

# DOMAIN_RULES.md

業務ルール抽出用。

これが最重要。

```text
あなたはドメインアナリストです。

このコードベースを分析し、
DOMAIN_RULES.mdを生成してください。

目的:
後続LLMがコードではなく
業務ルールを理解すること。

重要:
コード説明は禁止。
ビジネスルールを抽出してください。

含める内容:

# Domain Overview

業務領域概要

# Core Business Concepts

主要概念

例:

- 注文
- 顧客
- 契約
- 請求

# Business Rules

業務ルール一覧

例:

- 注文確定後は編集不可
- 仮登録ユーザーは決済不可

# State Machines

状態遷移

例:

Draft
↓
Submitted
↓
Approved
↓
Completed

# Validation Rules

入力制約

# Permission Rules

権限制約

# Financial Rules

料金計算

課金

割引

税計算

# Compliance Constraints

法的制約

監査要件

# Domain Assumptions

暗黙の前提

# Business Critical Rules

絶対に変更してはいけないルール

コードではなく
業務仕様書として記述してください。
```

---

# DATA_FLOW.md

データの流れ。

RAGやAIエージェントでは非常に有効。

```text
あなたはシステム設計者です。

DATA_FLOW.mdを生成してください。

目的:
データがどこから来て
どこへ流れるかを理解すること。

含める内容:

# Data Flow Overview

全体像

# User Input Flow

ユーザー入力から保存まで

# API Request Flow

リクエスト処理

# Database Write Flow

書き込み処理

# Database Read Flow

参照処理

# Event Flow

イベント処理

# Async Processing

ジョブ処理

# Cache Flow

キャッシュ利用

# External Data Sources

外部データ取得

# Data Ownership

各データの責任範囲

# Data Lifecycle

生成
更新
削除

# Sensitive Data Paths

個人情報

決済情報

認証情報

# Failure Points

データ欠損や不整合が起きる箇所

図解風に説明してください。

例:

User
 ↓
Controller
 ↓
Service
 ↓
Repository
 ↓
Database
```

---

# INTEGRATIONS.md

外部サービス。

実運用ではかなり重要。

```text
あなたはインテグレーションアーキテクトです。

INTEGRATIONS.mdを生成してください。

目的:
外部サービス変更時の影響を理解すること。

含める内容:

# Integration Overview

連携先一覧

# External Services

各サービスについて

- 目的
- 利用箇所
- 依存度

# Authentication Methods

API認証

OAuth

JWT

API Key

# Data Exchange

送受信データ

# Request Patterns

同期通信

非同期通信

Webhook

Batch

# Failure Handling

障害時挙動

# Retry Logic

再試行

# Rate Limits

利用制限

# Security Considerations

機密情報

# Vendor Lock-in Risks

依存リスク

# Integration Criticality

停止時の影響

Critical
High
Medium
Low

で分類してください。

外部依存関係を中心に説明してください。
```

---

# CHANGE_IMPACT_GUIDE.md

個人的には最もAI向き。

後続LLMの品質がかなり上がる。

```text
あなたはシニアソフトウェアアーキテクトです。

CHANGE_IMPACT_GUIDE.mdを生成してください。

目的:
変更時の影響範囲分析を支援すること。

含める内容:

# Change Impact Overview

影響分析の考え方

# Feature Dependency Matrix

主要機能の依存関係

# Module Dependency Matrix

モジュール依存関係

# Database Change Impact

テーブル変更時に影響する箇所

# API Change Impact

API変更時に影響する箇所

# Authentication Change Impact

認証変更時の影響

# UI Change Impact

画面変更時の影響

# Background Job Impact

ジョブ変更時の影響

# External Integration Impact

外部連携変更時の影響

# High Risk Components

危険コンポーネント

# Frequently Broken Areas

過去に壊れやすい箇所

# Regression Risk Map

変更内容ごとのリスク

例:

User Model変更
 ↓
Auth
 ↓
Billing
 ↓
Admin

# Safe Refactoring Zones

比較的安全な箇所

# Dangerous Refactoring Zones

慎重に扱う箇所

# Recommended Verification Checklist

変更後確認項目

機能追加
DB変更
API変更
認証変更

ごとに整理してください。

後続LLMが
「この修正で何が壊れるか」
を予測できるレベルで記述してください。
```

---

実際の運用で価値が高い順に並べると、私は次の順を推します。

1. `DOMAIN_RULES.md`
2. `CHANGE_IMPACT_GUIDE.md`
3. `ARCHITECTURE.md`
4. `AUTH.md`
5. `DATA_FLOW.md`
6. `DATABASE.md`
7. `API.md`
8. `INTEGRATIONS.md`
9. `BACKEND.md`
10. `FRONTEND.md`
11. `DEPLOYMENT.md`
12. `TROUBLESHOOTING.md`

なぜなら、後続の高性能モデルが苦手なのは「コードを読むこと」ではなく、「コードから設計意図や業務ルールを推測すること」だからです。特に `DOMAIN_RULES.md` と `CHANGE_IMPACT_GUIDE.md` は、生のコードを大量に渡すよりも、実際の保守・改修タスクでは大きな価値を持つことが多いです。

