30万token規模なら、最初から「全部入り自動化」にするより、**①全体把握用、②タスク実装用、③地図更新用**の3系統に分けるのが扱いやすいです。

以下は、現行Repomixの設定仕様を確認したうえで組んだテンプレートです。Repomixは `output.compress`、`output.patterns`、`include`、`ignore`、`output.includeFullDirectoryStructure` などを設定ファイルで指定できます。([Repomix][1])

# GPT-5.6 + Repomix 開発支援テンプレート

## 0. このテンプレートの目的

backend + frontend 合計約30万tokenのリポジトリを、GPT-5.6に毎回丸ごと渡さずに開発する。

基本方針は以下。

```text
                  Git Repository
                       │
             ┌─────────┴─────────┐
             │                   │
             ▼                   ▼
       圧縮版コード          通常版コード
       全体構造用             実装確認用
             │                   │
             ▼                   │
    PROJECT_MAP.md              │
    ARCHITECTURE.md             │
             │                   │
             └─────────┬─────────┘
                       ▼
                    GPT-5.6
                       │
                  必要部分だけ
                  フルコード取得
```

重要なのは、

> `--compress` の30万tokenを毎回送ることではない。

`--compress` は「どこを見るべきか」を判断するための全体構造コンテキストとして使い、実装時には関連ファイルだけを通常版で渡す。

Repomixのコード圧縮はTree-sitterを利用して、クラス・関数のシグネチャ、imports/exports、型などを残しながら実装詳細を削減する仕組み。したがって、詳細実装を読む用途では通常版を使う。

---

# 1. 推奨ディレクトリ構成

リポジトリ直下に以下を作る。

```text
.
├── backend/
├── frontend/
├── ...
│
├── ai-context/
│   ├── PROJECT_MAP.md
│   ├── ARCHITECTURE.md
│   ├── repo-compressed.xml
│   ├── task.xml
│   └── update.sh
│
└── repomix.config.json
```

`repo-compressed.xml` と `task.xml` は生成物なので、会社のルールに応じてGit管理対象外にしてもよい。

例えば `.gitignore`:

```gitignore
ai-context/repo-compressed.xml
ai-context/task.xml
```

`PROJECT_MAP.md` と `ARCHITECTURE.md` はチームで共有するならGit管理する。

---

# 2. repomix.config.json

まずリポジトリ直下に以下を置く。

```json
{
  "$schema": "https://repomix.com/schemas/latest/schema.json",

  "output": {
    "filePath": "ai-context/repo-compressed.xml",
    "style": "xml",

    "compress": true,

    "fileSummary": true,
    "directoryStructure": true,
    "includeFullDirectoryStructure": true,

    "removeComments": false,
    "removeEmptyLines": false,

    "topFilesLength": 10,

    "git": {
      "sortByChanges": false,
      "includeDiffs": false,
      "includeLogs": false
    }
  },

  "include": [
    "backend/**/*",
    "frontend/**/*",
    "shared/**/*",
    "packages/**/*",
    "libs/**/*",
    "docs/**/*",
    "*.md",
    "*.json",
    "*.yaml",
    "*.yml"
  ],

  "ignore": {
    "useGitignore": true,
    "useDotIgnore": true,
    "useDefaultPatterns": true,

    "customPatterns": [
      "**/node_modules/**",
      "**/dist/**",
      "**/build/**",
      "**/coverage/**",
      "**/.next/**",
      "**/.nuxt/**",
      "**/.turbo/**",
      "**/target/**",

      "**/*.log",
      "**/*.map",

      "**/.env",
      "**/.env.*",

      "**/*.pem",
      "**/*.key",
      "**/*.crt",

      "**/vendor/**",
      "**/tmp/**",
      "**/temp/**"
    ]
  },

  "security": {
    "enableSecurityCheck": true
  },

  "tokenCount": {
    "encoding": "o200k_base"
  }
}
```

## 注意

`backend`、`frontend`、`shared`、`packages`、`libs` は例なので、実際のリポジトリ構成に合わせて変更する。

また、`.gitignore`等の除外ルールはRepomix側でも尊重されるため、既存のGit管理外ファイルが原則として対象外になる。RepomixにはSecretlintによるセキュリティチェックもあります。([Repomix][1])

ただし、

**AIに送信してよい情報かどうかの最終確認は必ず社内ルールを優先する。**

---

# 3. update.sh

`ai-context/update.sh` を作る。

```bash
#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONTEXT_DIR="$ROOT_DIR/ai-context"

cd "$ROOT_DIR"

mkdir -p "$CONTEXT_DIR"

echo "========================================"
echo " GPT-5.6 AI Context Generator"
echo "========================================"
echo ""

echo "[1/3] Generating compressed repository..."

npx repomix@latest \
  --compress \
  -o "$CONTEXT_DIR/repo-compressed.xml"

echo ""
echo "[2/3] Repository token distribution..."
echo ""

npx repomix@latest \
  --token-count-tree 1000

echo ""
echo "[3/3] Done."
echo ""

echo "Generated:"
echo "  $CONTEXT_DIR/repo-compressed.xml"
echo ""

echo "Next:"
echo "  1. Upload repo-compressed.xml to GPT-5.6"
echo "  2. Upload PROJECT_MAP.md"
echo "  3. Upload ARCHITECTURE.md"
echo "  4. Run the map-update prompt"
```

実行権限を付ける。

```bash
chmod +x ai-context/update.sh
```

実行。

```bash
./ai-context/update.sh
```

Repomixは `npx repomix@latest` でインストールなしに実行できます。また `--token-count-tree` でディレクトリ・ファイルごとのtoken分布を確認できます。([Repomix][2])

---

# 4. 最初の一回だけ：PROJECT_MAP.md / ARCHITECTURE.mdを作る

`./ai-context/update.sh` を実行。

その後、

```text
ai-context/repo-compressed.xml
```

をGPT-5.6にアップロードする。

以下のプロンプトを使用する。

## Prompt 1：初回マップ生成

```text
このファイルはリポジトリ全体をRepomixのコード圧縮機能で
構造中心にまとめたものです。

このリポジトリを今後のAIによる開発支援に利用するため、
以下の2つのMarkdownファイルを作成してください。

# PROJECT_MAP.md

以下を整理してください。

- プロジェクトの目的
- repository全体の構成
- backend
- frontend
- shared code
- libraries
- infrastructure
- scripts
- tests
- docs

各領域について、

- ディレクトリ
- 主要ファイル
- 役割
- 関係する主要モジュール

を整理してください。

特に以下を可能な限り特定してください。

- APIの入口
- Controller / Handler
- Service
- Repository / DAO
- DBアクセス
- Model / Entity
- 認証
- 認可
- 外部API
- メッセージング
- バッチ
- frontendの主要画面
- frontendのAPI client
- state management
- 共通コンポーネント
- テスト

必ず具体的なファイルパスを記載してください。

---

# ARCHITECTURE.md

以下を整理してください。

- システム全体の構成
- frontend → backend → database の関係
- APIリクエストの流れ
- 認証・認可の流れ
- 主要なデータフロー
- backend内部の主要な依存関係
- frontend内部の主要な依存関係
- 外部サービスとの接続
- shared moduleの役割
- 変更影響範囲が広くなりやすい領域

可能であれば簡単なASCII図も使用してください。

例:

frontend
   │
   ▼
API Client
   │
   ▼
Controller
   │
   ▼
Service
   │
   ▼
Repository
   │
   ▼
Database

---

# 共通ルール

非常に重要です。

1. コードから確認できる情報を優先する
2. 推測でアーキテクチャを作らない
3. 判断できない場合は「不明」と書く
4. 推測した場合は「推測」と明記する
5. 実装コードを大量に転載しない
6. AIが「次にどのファイルを読むべきか」を判断できることを最優先する
7. 人間向けの立派な設計書ではなく、AI向けのナビゲーション情報として作る
8. できるだけ簡潔にする
9. ファイルパスを正確に記載する
10. 存在しないファイルやディレクトリを作らない

最後に、

「機能追加・バグ修正時に最初に確認すべきファイル」

を領域別に整理してください。
```

---

# 5. 普段の開発：影響範囲を調べる

例えば、

> ユーザー削除APIを管理者だけ実行可能にしたい

というタスクが来たとする。

このとき最初から30万tokenを渡さない。

まず、

```text
PROJECT_MAP.md
ARCHITECTURE.md
repo-compressed.xml
```

を渡す。

## Prompt 2：影響範囲調査

```text
以下の開発タスクについて、実装前の影響範囲調査をしてください。

【タスク】
ここに開発タスクを記載する

まだコードを変更しないでください。

PROJECT_MAP.md
ARCHITECTURE.md
repo-compressed.xml

を利用して、以下を調査してください。

1. 変更が必要になる可能性があるファイル
2. 変更が必要になる可能性があるmodule
3. 関連するAPI
4. frontendへの影響
5. backendへの影響
6. DBへの影響
7. 認証・認可への影響
8. 外部サービスへの影響
9. テストへの影響
10. 既存機能への副作用の可能性

各候補について、

ファイル:
理由:
確認すべきポイント:

の形式で整理してください。

最後に、

【Implementation Context】

として、

「実装時にフルコードを読み込むべきファイル」

だけを一覧にしてください。

重要:

- まだ実装しない
- 推測とコードから確認できる事実を区別する
- 不要なファイルを大量に候補に入れない
- 変更範囲を最小化する
- PROJECT_MAP.mdだけを根拠にせず、repo-compressed.xmlの情報も確認する
```

ここでGPT-5.6から、

```text
Implementation Context:

backend/src/controller/user_controller.ts
backend/src/service/user_service.ts
backend/src/auth/permission.ts
backend/src/repository/user_repository.ts
backend/src/test/user_test.ts

frontend/src/api/user.ts
frontend/src/pages/admin/UserManagement.tsx
```

などが返ってきたら、そのファイルだけを通常版Repomixで取得する。

---

# 6. task.xmlを作る

一番簡単なのは、

```bash
npx repomix \
  --include "backend/src/controller/user_controller.ts,backend/src/service/user_service.ts,backend/src/auth/permission.ts,backend/src/repository/user_repository.ts,backend/src/test/user_test.ts,frontend/src/api/user.ts,frontend/src/pages/admin/UserManagement.tsx" \
  -o ai-context/task.xml
```

という形。

Repomixは `--include` でglobまたはカンマ区切りの対象を指定できます。([Repomix][3])

実際にはファイル数が多い場合、

```text
backend/src/user/**
backend/src/auth/**
frontend/src/user/**
```

のようなディレクトリ単位でもよい。

---

# 7. 実装する

GPT-5.6に、

```text
PROJECT_MAP.md
ARCHITECTURE.md
task.xml
```

をアップロード。

そして以下。

## Prompt 3：実装

```text
以下の開発タスクを実装してください。

【タスク】
ここに開発タスクを記載する

提供したファイル:

- PROJECT_MAP.md
- ARCHITECTURE.md
- task.xml

まずtask.xmlの実装と、
事前に作成した影響範囲分析を照合してください。

実装前に、

「今回の変更対象ファイル」

を一覧にしてください。

その後、実装してください。

実装ルール:

1. 既存仕様を維持する
2. 変更範囲を最小限にする
3. 不要なリファクタリングをしない
4. 既存の設計パターンに従う
5. 既存の命名規則に従う
6. 必要なテストを追加・修正する
7. 既存テストを壊さない
8. 推測で新しいアーキテクチャを導入しない
9. task.xmlにないファイルを変更する必要がある場合は、
   その理由を明示する
10. 可能な限り小さいdiffで実装する

実装後、以下を出してください。

## Changed Files

- ファイル
- 変更理由

## Behavior Change

今回何が変わったか。

## Tests

追加・修正したテスト。

## Potential Risks

今回の変更による潜在的な影響。

## Additional Files

task.xmlに含まれていないファイルの変更が必要になった場合は、
そのファイルと理由。
```

---

# 8. 地図の更新

大きな機能追加をしたら、

```bash
./ai-context/update.sh
```

を実行する。

新しい

```text
repo-compressed.xml
```

を生成する。

そのうえで、

```text
PROJECT_MAP.md
ARCHITECTURE.md
repo-compressed.xml
```

をGPT-5.6に渡して、以下。

```text
現在のPROJECT_MAP.mdとARCHITECTURE.mdを、
最新のrepo-compressed.xmlと照合してください。

今回のコード変更によって古くなった情報だけを更新してください。

特に以下を確認してください。

- 新規ディレクトリ
- 新規主要モジュール
- APIの追加・変更
- frontend/backend間の変更
- DBアクセスの変更
- 認証・認可の変更
- 外部サービス連携の変更
- shared moduleの変更
- 主要な依存関係の変更

ルール:

- 変更されていない説明は維持する
- 推測で情報を追加しない
- 存在しないファイルを記載しない
- 詳細実装を書かない
- AIが次に読むべきファイルを判断できることを優先する

更新が不要な場合は「更新不要」と回答してください。
```

---

# 9. 実際の開発フロー

最終的にはこれだけ。

```text
┌─────────────────────────────┐
│ ① タスク発生                │
└──────────────┬──────────────┘
               ▼
┌─────────────────────────────┐
│ PROJECT_MAP                 │
│ ARCHITECTURE                │
│ repo-compressed.xml         │
└──────────────┬──────────────┘
               ▼
       GPT-5.6 影響範囲調査
               │
               ▼
┌─────────────────────────────┐
│ 必要ファイルだけ抽出        │
│ task.xml                    │
└──────────────┬──────────────┘
               ▼
       GPT-5.6で実装
               │
               ▼
          テスト実行
               │
               ▼
          git diff確認
               │
               ▼
       必要なら地図更新
```

---

# 10. 30万tokenリポジトリでの使い分け

| 作業                     | GPT-5.6へ渡すもの                     |
| ---------------------- | -------------------------------- |
| 「このプロジェクトどうなってる？」      | PROJECT_MAP + ARCHITECTURE       |
| 影響範囲調査                 | PROJECT_MAP + ARCHITECTURE + 圧縮版 |
| 小さなバグ修正                | 地図 + 対象ファイル                      |
| 通常の機能追加                | 地図 + 関連ファイル                      |
| frontend/backendをまたぐ変更 | 地図 + 圧縮版 + 関連ファイル                |
| 大規模設計変更                | 圧縮版 + 必要なフルコード                   |
| コードレビュー                | git diff + 関連ファイル                |
| テスト失敗調査                | エラーログ + 関連ファイル                   |
| 地図更新                   | 圧縮版 + 現在の地図                      |

**30万tokenを毎回送るのは例外扱い**にする。

---

# 11. さらにコストを削りたい場合

Repomixにはファイルごとに、

```text
Full
Compressed
Directory Structure Only
```

という3段階の扱いを設定できる `output.patterns` があります。最初にマッチしたパターンが適用されます。([Repomix][1])

そのため、将来的には例えば、

```json
{
  "output": {
    "compress": true,

    "patterns": [
      {
        "pattern": "docs/**/*",
        "compress": false
      },
      {
        "pattern": "frontend/src/components/**/*",
        "compress": true
      },
      {
        "pattern": "backend/src/core/**/*",
        "compress": true
      },
      {
        "pattern": "**/*.test.*",
        "compress": true
      }
    ]
  }
}
```

のように、重要な部分だけ詳細度を変えることもできる。

ただし、**最初からここまで複雑にしないことを推奨**する。

まずは、

```text
全体 → compress
必要部分 → full
```

だけで運用する。

---

# 12. 重要：30万tokenが本当にどれくらい減るか測る

導入前に、

```bash
repomix --token-count-tree
```

を実行する。

その後、

```bash
repomix --compress
```

で圧縮後のサイズを見る。

Repomix自身がtoken数を表示するので、

```text
Before
300,000 tokens

After
？？？ tokens
```

を実測する。

さらに、実際の開発タスクで、

```text
従来:
300K + 会話履歴 + プロンプト

新方式:
地図 + 圧縮版 + task.xml
```

を比較する。

ここで初めて、**自社のGPT-5.6環境でどれくらいコストが下がったか**を判断する。

---

# 13. 最初にやることは3つだけ

複雑そうに見えるが、最初はこれだけ。

### ① 設定を追加

```text
repomix.config.json
```

### ② スクリプトを追加

```text
ai-context/update.sh
```

### ③ 一度だけGPT-5.6に作らせる

```text
PROJECT_MAP.md
ARCHITECTURE.md
```

その後の開発は、

```text
地図
 ↓
影響範囲調査
 ↓
必要ファイルだけRepomix
 ↓
実装
```

になる。

---

# 14. この構成の考え方

この仕組みでは、Repomixに「設計書を作らせる」ことを期待していない。

役割を分ける。

```text
Repomix
    ↓
「コードをAIに渡しやすい形にする」

GPT-5.6
    ↓
「コードから構造・依存関係を理解する」

PROJECT_MAP.md
    ↓
「どこに何があるか」

ARCHITECTURE.md
    ↓
「どうつながっているか」

task.xml
    ↓
「今回の実装に必要な詳細コード」
```

この4つを分離することで、

**「30万tokenのリポジトリを毎回読ませる」**

から、

**「30万tokenのリポジトリから、今回必要な2〜5万token程度を選んで読ませる」**

という運用に変えるのが狙い。

なお、実際にどこまで減るかはリポジトリの言語・生成コード・テスト量・重複などで大きく変わるため、`--compress` の削減率を固定値として期待するのではなく、`--token-count-tree` と実際の出力で測るのが安全です。Repomix公式も、大規模リポジトリではinclude/ignore/compressを組み合わせて対象範囲を絞ることを案内しています。([Repomix][4])

この構成なら、**最初は30万tokenの全体構造を1回読ませて地図を作る → 普段は地図から必要箇所だけ読む**、という運用にできます。

特に今回の目的が「月額上限を守ること」なら、私は `output.patterns` の細かい最適化より、まずこの **Full / Compressed の2段階運用**から始めるのをおすすめします。実測してから3段階化したほうが、設定自体のメンテナンスコストを増やさずに済みます。

[1]: https://repomix.com/guide/configuration?utm_source=chatgpt.com "Configuration | Repomix"
[2]: https://repomix.com/?utm_source=chatgpt.com "Repomix | Pack your codebase into AI-friendly formats"
[3]: https://repomix.com/guide/command-line-options?utm_source=chatgpt.com "Command Line Options | Repomix"
[4]: https://repomix.com/guide/faq?utm_source=chatgpt.com "FAQ and Troubleshooting | Repomix"
