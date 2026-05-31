これはかなり有効な手法で、実際には「要約」よりも**AI向けのコンテキストパック（Context Pack）**を作るイメージが近い。

単なる要約だと、

> 認証機能があります。ユーザー管理機能があります。

みたいな情報しか残らず、高性能モデルがコード修正する際には役に立たない。

むしろ高性能モデルが後から読むことを前提に、

* システム構造
* データフロー
* 依存関係
* 命名規則
* 設計意図

を残した方が価値が高い。

---

## プロンプト例1: 全体構造分析

安いモデルにリポジトリ全体を読ませた後

```text
あなたはソフトウェアアーキテクトです。

このコードベースを分析し、
後続の別LLMが理解できるように
AI向け設計書を作成してください。

以下の形式で出力してください。

# Project Overview

- システムの目的
- 想定ユーザー
- 主な機能

# Architecture

- 全体構成
- レイヤー構造
- 各ディレクトリの責務

# Important Flows

- ログイン処理
- データ登録処理
- API通信
- 権限管理

# Key Components

各主要モジュールについて

- 役割
- 依存先
- 呼び出し元

# Coding Conventions

- 命名規則
- 設計パターン
- 例外処理方針

# Known Risks

- 技術的負債
- 複雑な箇所
- 修正時の注意点

後続LLMが改修作業できるレベルの詳細さで記述してください。
```

---

## プロンプト例2: モジュールマップ生成

これがかなり強い。

```text
コードベース全体から
モジュール間の依存関係マップを作成してください。

以下の形式で出力してください。

Module:
責務:

Depends On:
-

Used By:
-

Key Files:
-

Public API:
-

Data Models:
-

Business Rules:
-
```

結果として

```text
Auth Module
 ├─ User Repository
 ├─ JWT Service
 └─ Session Manager

User Module
 ├─ User Repository
 ├─ Profile Service
 └─ Auth Module
```

みたいな情報が残る。

---

## プロンプト例3: AI引継ぎ資料作成

個人的にはこれが一番実用的。

```text
あなたの役割は
別のLLMへの引継ぎ資料作成です。

今後このコードベースを知らない高性能LLMが
保守開発を行います。

そのため以下を作成してください。

1. システム概要
2. 主要機能一覧
3. ディレクトリ構造
4. データモデル一覧
5. API一覧
6. 認証認可方式
7. イベントフロー
8. 状態管理方式
9. 重要な設計判断
10. 改修時に壊れやすい箇所

トークン節約のため、
重要度の低い実装詳細は省略し、
設計上重要な情報を優先してください。
```

---

## プロンプト例4: AI専用ナレッジベース生成

大規模案件ならこれが最もコスパがいい。

```text
このコードベースを分析し、
複数のLLMが共有する知識ベースを作成してください。

出力形式:

## Domain Concepts

## Business Rules

## Data Flow

## External Services

## Database Schema

## Authentication

## Authorization

## Background Jobs

## Error Handling

## Deployment

## Development Guidelines

## Frequently Modified Areas

## Dangerous Areas
```

これを `AI_CONTEXT.md` として保存しておく。

---

## さらに効果的な方法

巨大案件（数十万〜数百万行）では、1つの要約ファイルではなく階層化する。

```text
AI_CONTEXT.md
├─ PROJECT_OVERVIEW.md
├─ ARCHITECTURE.md
├─ DATABASE.md
├─ API.md
├─ AUTH.md
├─ FRONTEND.md
├─ BACKEND.md
├─ DEPLOYMENT.md
└─ TROUBLESHOOTING.md
```

そして高性能モデルには最初に

```text
まず AI_CONTEXT.md を読み、
必要に応じて関連ドキュメントを参照してください。
```

と指示する。

この方法だと、安価なモデルで数百万トークンの解析を一度行い、その成果物を何度も高性能モデルに使い回せるので、実運用ではかなりコスト効率が良い。

