**`repomix --compress` だけで `PROJECT_MAP.md` / `ARCHITECTURE.md` が自動生成されるわけではありません。**

`--compress` は、コードそのものを「構造が分かる程度に圧縮する」機能です。Tree-sitterで解析して、関数・メソッドのシグネチャ、クラス、型、インターフェースなどを残し、実装詳細を削ります。つまり**「AIに渡すための材料を圧縮する機能」**であって、「設計書を作る機能」ではありません。([Repomix][1])

なので、次の構成がかなり現実的です。

---

# 結論：Repomix + GPT-5.6で自動生成する

イメージはこれです。

```text
Gitリポジトリ
      │
      ▼
  Repomix
      │
      ├── 通常版
      │    └─ 正確な実装を読む用
      │
      └── --compress
           └─ 全体構造を把握する用
                │
                ▼
             GPT-5.6
                │
                ├── PROJECT_MAP.md
                └── ARCHITECTURE.md
```

つまり、

**Repomixが「材料を作る」 → GPT-5.6が「地図を作る」**

という役割分担です。

---

# 1. 最初に一度だけ作る

リポジトリのルートで、

```bash
mkdir -p ai-context

repomix --compress -o ai-context/repo-compressed.xml
```

これだけ。

現在のRepomixでは `--compress` はTree-sitterによるコード構造抽出を行うので、通常の全ソースよりかなり「構造を見る」用途に向いています。([Repomix][2])

さらに、Repomix自身がディレクトリ構造やファイルサマリーも出力できます。

---

# 2. GPT-5.6に地図を作らせる

社内Chat UIに、

```text
ai-context/repo-compressed.xml
```

をアップロードします。

そして、これを投げます。

```text
このリポジトリを「今後のソフトウェア開発タスクでAIが参照するための地図」として整理してください。

以下の2ファイルを作成してください。

## 1. PROJECT_MAP.md

以下を整理してください。

- プロジェクトの目的
- repository全体のディレクトリ構造
- backend / frontend / infrastructure などの主要領域
- 各主要ディレクトリの役割
- 主要なモジュール
- APIの入口
- DBアクセス
- 認証・認可
- 外部サービス連携
- テスト
- 設定
- frontendとbackendの主要な対応関係

各項目について、
「具体的にどのファイルを見ればよいか」
が分かるようにファイルパスを記載してください。

## 2. ARCHITECTURE.md

以下を整理してください。

- システム全体の構成
- frontend → backend → database の流れ
- 主要モジュール間の依存関係
- APIリクエストの流れ
- 認証・認可の流れ
- 重要なデータフロー
- 外部サービスとの接続
- 変更時に影響範囲が広くなりやすい領域
- frontendとbackendの対応関係

重要なルール:

1. コードから確認できる事実を優先する
2. 推測は推測と明記する
3. 存在しない仕組みを想像して補完しない
4. 実装コードそのものを大量に転載しない
5. 「どのファイルを見ればよいか」が分かることを最優先する
6. AIが後から変更影響範囲を調査するときに役立つ内容にする
7. 冗長な説明は避ける

最後に、

「機能追加・バグ修正を行う際、最初に確認すべきファイル」

を重要度順ではなく、領域別に整理してください。
```

これでかなりの部分を作れます。

ただし、**ここで注意点があります。**

---

# 3. `--compress`だけで全部分かるのか？

**答えは「No」です。**

ここはかなり重要です。

例えば元コードが、

```typescript
class UserService {
    async createUser(data: CreateUserRequest) {
        // 200行の複雑な処理
    }
}
```

だった場合、圧縮版では概念的には、

```typescript
class UserService {
    async createUser(data: CreateUserRequest)
}
```

のような**構造情報**が中心になります。

Repomix公式も、`--compress` は実装詳細を削って、関数・メソッド・クラス・型などの重要な構造を残すものと説明しています。([Repomix][1])

なので、

### `--compress` が得意

```text
・このプロジェクトには何がある？
・どんなクラスがある？
・どんなAPIがある？
・どんなinterface/typeがある？
・どのモジュールが存在する？
・大体どこに何がある？
```

### `--compress` が苦手

```text
・この処理はなぜこうなっている？
・このif文を変更すると何が壊れる？
・DBへの具体的なクエリは？
・このバグの原因は？
・この関数の細かい副作用は？
・トランザクション処理の具体的な実装は？
```

です。

---

# 4. だから「3段階」にする

あなたの300K token級のリポジトリなら、私はこうします。

```text
                 ┌─────────────────────┐
                 │     Git Repository  │
                 └──────────┬──────────┘
                            │
                ┌───────────┴───────────┐
                ▼                       ▼
       Repomix --compress          Repomix 通常版
                │                       │
                ▼                       ▼
        「全体構造を理解」          「実装を理解」
                │                       │
                ▼
       PROJECT_MAP.md
       ARCHITECTURE.md
                │
                └──────────┐
                           ▼
                     GPT-5.6
                           │
                 必要なコードだけ追加
                           │
                           ▼
                       実装
```

これがポイントです。

---

# 5. そして、毎回300Kを送らない

例えばユーザーから、

> 「ユーザー削除APIで、管理者だけが削除できるように変更して」

と言われたとします。

最初にGPT-5.6へ渡すのは、

```text
PROJECT_MAP.md
ARCHITECTURE.md
repo-compressed.xml
```

です。

GPT-5.6に、

```text
この変更の影響範囲を調査してください。

まだ実装しないでください。

以下を特定してください。

- 変更対象となるbackendファイル
- 認証・認可関連ファイル
- frontend側で変更が必要なファイル
- test
- API定義
- DB関連
- 変更によって影響を受ける可能性のあるファイル

各ファイルについて、
「なぜ確認が必要なのか」を1〜2行で説明してください。

最後に、実装時に必要なファイルだけを一覧にしてください。
```

とする。

GPT-5.6が、

```text
変更候補:

backend/src/controllers/user.controller.ts
backend/src/services/user.service.ts
backend/src/auth/permission.ts
backend/src/repositories/user.repository.ts

backend/test/user.test.ts

frontend/src/api/user.ts
frontend/src/pages/UserAdmin.tsx
```

みたいに絞ります。

---

# 6. そこで「通常版Repomix」

ここで初めて、

```bash
repomix \
  --include "backend/src/controllers/user.controller.ts,backend/src/services/user.service.ts,backend/src/auth/permission.ts,backend/src/repositories/user.repository.ts,backend/test/user.test.ts,frontend/src/api/user.ts,frontend/src/pages/UserAdmin.tsx" \
  -o ai-context/task.xml
```

のように、**必要なコードだけフルで取得する**。

Repomixは `--include` で対象ファイルを絞れます。大規模リポジトリではinclude/ignoreと`--compress`を組み合わせて対象範囲を狭めることも公式に推奨されています。([Repomix][3])

そして、

```text
PROJECT_MAP.md
ARCHITECTURE.md
task.xml
```

をGPT-5.6に渡して、

```text
先ほどの影響範囲分析と実際のコードを照合してください。

影響範囲に漏れがないか確認してください。

問題がなければ実装してください。

実装時のルール:
- 不要なリファクタリングをしない
- 既存仕様を維持する
- 変更範囲を最小限にする
- 必要なテストを追加・修正する
- 最後に変更ファイル一覧と変更理由を出す
```

とする。

---

# 7. ここまでを「ほぼワンコマンド」にする

さらに楽にできます。

例えばリポジトリに、

```text
ai-context/
├── PROJECT_MAP.md
├── ARCHITECTURE.md
├── repo-compressed.xml
└── task.xml
```

を置いて、

```bash
./ai-context/update.sh
```

というスクリプトを作る。

中身はまず、

```bash
#!/bin/bash

set -e

mkdir -p ai-context

echo "Generating compressed repository..."

repomix \
  --compress \
  -o ai-context/repo-compressed.xml

echo "Repository context generated."

echo ""
echo "Next:"
echo "1. Upload ai-context/repo-compressed.xml to GPT-5.6"
echo "2. Ask GPT-5.6 to update PROJECT_MAP.md and ARCHITECTURE.md"
```

くらいでいい。

---

# 8. さらに一歩進めるなら「地図更新専用」

ここからが本当に便利です。

`PROJECT_MAP.md` と `ARCHITECTURE.md` を毎回全生成するのではなく、

```bash
./ai-context/update.sh
```

↓

```text
repo-compressed.xml
```

を生成

↓

GPT-5.6に

```text
現在のPROJECT_MAP.mdとARCHITECTURE.mdも添付します。

今回のrepository構造と比較してください。

変更によって古くなった情報だけ修正してください。

変更不要な部分は維持してください。

特に以下を確認してください。

- 新規ディレクトリ
- 新規主要モジュール
- API変更
- frontend/backend間の変更
- DB構造の変更
- 認証・認可の変更
- 外部サービス連携の変更
- 大きな依存関係変更

推測で情報を追加しないでください。
```

とする。

つまり、

**人間はドキュメントをメンテナンスしない。**

GPT-5.6にメンテナンスさせる。

---

# 9. 実はRepomixにはもっと面白い機能がある

現在のRepomixでは、単純な全体圧縮だけではなく、**ファイルごとに「完全版」「圧縮版」「ディレクトリ構造だけ」を使い分ける設定**もできます。`output.patterns` がそのための機能です。([Repomix][4])

例えば、

```text
重要なAPI
    ↓
完全なソース

普通のService
    ↓
圧縮

大量のDTO
    ↓
圧縮

README
    ↓
完全

build/dist
    ↓
除外
```

みたいな構成が可能です。

これはあなたの**300K token問題にかなり相性がいい**です。

---

# 10. 私なら最終的にこうする

最初は複雑にしません。

### Step 1

```bash
repomix --compress -o ai-context/repo-compressed.xml
```

### Step 2

GPT-5.6に生成させる。

```text
repo-compressed.xml
        ↓
PROJECT_MAP.md
ARCHITECTURE.md
```

### Step 3

普段の開発では、

```text
PROJECT_MAP.md
ARCHITECTURE.md
        +
必要なコードだけ
```

をGPT-5.6に渡す。

### Step 4

大規模変更のときだけ、

```text
repo-compressed.xml
```

も渡す。

### Step 5

地図が古くなったら、

```bash
repomix --compress -o ai-context/repo-compressed.xml
```

してGPT-5.6に更新させる。

---

## そして、かなり重要なこと

**「300K → 50Kに圧縮できるから得」という考え方だけではありません。**

一番大きいのは、

> **毎回300Kのコード全文をGPT-5.6に読ませる必要がなくなる**

ことです。

例えば、

| 用途           | 入力するもの                               |
| ------------ | ------------------------------------ |
| 全体構造を確認      | `PROJECT_MAP.md` + `ARCHITECTURE.md` |
| 影響範囲調査       | 上記 + `repo-compressed.xml`           |
| 普通の機能追加      | 上記 + 関連コード                           |
| バグ修正         | 上記 + バグ関連コード                         |
| 大規模アーキテクチャ変更 | 必要なら全体                               |
| コードレビュー      | `git diff` + 関連コード                   |

という使い分けにします。

**つまり「圧縮ファイルを毎回送る」のがゴールではありません。**

`--compress` は、**GPT-5.6が「どこを読めばいいか」を判断するための索引として使う**のが一番おいしいです。

なお、Repomixは現在 `repomix.config.json` に設定をまとめられ、チームで同じinclude/ignore設定を再利用できます。`--init` で設定ファイルを作ることもできます。([Repomix][4])

[1]: https://repomix.com/guide/code-compress?utm_source=chatgpt.com "Code Compression | Repomix"
[2]: https://repomix.com/ja/guide/command-line-options?utm_source=chatgpt.com "コマンドラインオプション | Repomix"
[3]: https://repomix.com/guide/faq?utm_source=chatgpt.com "FAQ and Troubleshooting | Repomix"
[4]: https://repomix.com/guide/configuration?utm_source=chatgpt.com "Configuration | Repomix"

