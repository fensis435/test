既存コードへの機能追加・修正が中心」**に合わせて、実際に開発者がそのまま使える運用マニュアルとしてまとめます。
特に「何を作るか」「どう作るか」「どの順番でアップロードするか」「何をプロンプトに書くか」まで一式にします。

# GPT-5.6 × Repomix

## 既存コードの機能追加・修正向け利用マニュアル

### 1. このマニュアルの目的

既存のBackend / FrontendコードをGPT-5.6に読み込ませて修正する際、

* リポジトリ全体を毎回アップロードすると入力トークンが非常に多くなる
* 部分的なコードだけ渡すと、全体への影響範囲を見落とす
* 会話履歴も入力トークンとして蓄積する
* 月間のLLM利用上限に到達しやすい

という問題を避ける。

基本方針は、

> **「全体をコードとして読ませる」のではなく、「全体構造を把握させてから、必要なコードだけ読ませる」**

とする。

---

# 2. 基本的な利用方法

従来：

```text
リポジトリ全体
    ↓
Repomix
    ↓
約300,000 tokens
    ↓
GPT-5.6
    ↓
修正
```

今後：

```text
リポジトリ
    ↓
① プロジェクト構造
② 圧縮コード
③ 必要な場合だけ完全コード
    ↓
GPT-5.6
    ↓
影響範囲を特定
    ↓
必要コードだけ追加
    ↓
実装
```

---

# 3. 事前に用意するファイル

プロジェクトごとに、最低限以下を用意する。

```text
ai-context/
├── PROJECT_MAP.md
├── ARCHITECTURE.md
└── repomix-compressed.xml
```

さらに必要に応じて、

```text
ai-context/
└── repomix-full.xml
```

を作る。

それぞれの役割は以下。

| ファイル                     | 用途                       | 頻度    |
| ------------------------ | ------------------------ | ----- |
| `PROJECT_MAP.md`         | 全体構造・主要ファイル・依存関係         | 常用    |
| `ARCHITECTURE.md`        | Backend/Frontend/API等の設計 | 常用    |
| `repomix-compressed.xml` | 全体コードの構造把握               | 調査時   |
| `repomix-full.xml`       | 実際のコード修正                 | 必要時のみ |

---

# 4. PROJECT_MAP.mdの作り方

まずプロジェクトのディレクトリ構造を確認する。

```bash
tree -L 4
```

Windows等でtreeが使えない場合は、IDEやファイル一覧から作ってもよい。

例えば、

```text
project/
├── backend/
│   ├── controller/
│   ├── service/
│   ├── repository/
│   └── model/
├── frontend/
│   ├── pages/
│   ├── components/
│   ├── hooks/
│   └── api/
└── tests/
```

を確認する。

次に、以下のような `PROJECT_MAP.md` を作る。

```markdown
# Project Map

## Overview

このプロジェクトは以下の構成。

- Backend: xxx
- Frontend: xxx
- Database: xxx
- API: REST / GraphQL
- Authentication: xxx

## Backend

### Controller

backend/controller/

APIリクエストを受け付ける。

主要クラス：
- UserController
- OrderController
- ProductController

### Service

backend/service/

業務ロジックを担当。

主要クラス：
- UserService
- OrderService
- ProductService

### Repository

backend/repository/

DBアクセスを担当。

主要クラス：
- UserRepository
- OrderRepository
- ProductRepository

## Frontend

### Pages

frontend/pages/

画面を担当。

### Components

frontend/components/

UIコンポーネント。

### Hooks

frontend/hooks/

API呼び出し・状態管理。

### API

frontend/api/

Backend APIとの通信。

## Typical Dependency

Frontend
  ↓
API Client
  ↓
Controller
  ↓
Service
  ↓
Repository
  ↓
Database
```

### ポイント

ここに**全コードを書く必要はない**。

目的は、

> 「このプロジェクトには何があり、どこからどこにつながっているか」

をGPT-5.6に伝えること。

---

# 5. ARCHITECTURE.mdの作り方

プロジェクト固有のルールをまとめる。

例えば、

```markdown
# Architecture

## Backend

ControllerからRepositoryを直接呼び出さない。

Controller
→ Service
→ Repository

という構造を維持する。

## Frontend

Page
→ Hook
→ API Client

という構造を基本とする。

## API

既存APIのURLとレスポンス形式は原則変更しない。

## Database

DB migrationにはFlywayを使用する。

## Testing

Serviceを変更した場合はServiceのUnit Testを確認する。

APIを変更した場合はIntegration Testも確認する。

## Important Constraints

以下は原則変更しない。

- Authentication module
- LegacyOrder module
- Database schema
```

これは**GPT-5.6に毎回説明している内容をファイル化する**もの。

---

# 6. Repomixのインストール

Repomixがまだ入っていない場合は、Node.js環境で、

```bash
npx repomix
```

で利用できる。

グローバルインストールする場合は、

```bash
npm install -g repomix
```

とする。

---

# 7. 全体構造を把握するためのRepomix

まず通常のRepomixではなく、**圧縮版**を作る。

```bash
repomix --compress
```

これによって、コードの実装詳細をある程度省略しつつ、クラス・関数などの構造を把握しやすい形にする。

RepomixにはTree-sitterを利用した`--compress`があり、コードの構造を残しながらトークン数を削減できる。([repomix.com](https://repomix.com/?utm_source=chatgpt.com))

生成されたファイルのトークン数を確認する。

**目標は「30万tokens → 可能な限り小さくする」こと。**

例えば、

```text
通常版      300K
compressed  60K
```

なら、かなり改善している。

---

# 8. Repomixの対象外を設定する

`node_modules`、ビルド成果物、バイナリ、ログなどは絶対に不要。

例えば、

```text
repomix
```

の設定ファイルを利用して、

```text
node_modules
dist
build
coverage
.git
*.lock
*.min.js
*.map
```

などを除外する。

Repomixではinclude / ignore patternを指定できる。([repomix.com](https://repomix.com/?utm_source=chatgpt.com))

特に、

```text
.git/
node_modules/
dist/
build/
coverage/
```

は除外する。

---

# 9. 最初のGPT-5.6への入力

ここでは**まだ実装させない**。

アップロードするファイル：

```text
PROJECT_MAP.md
ARCHITECTURE.md
repomix-compressed.xml
```

そして以下のプロンプトを使用する。

# 役割

あなたは既存ソフトウェアの保守・改修を支援するシニアソフトウェアエンジニアです。

# 重要なルール

この段階ではコードを変更しないでください。

目的は、ユーザーの要求に対して、
「どのコードが影響を受ける可能性があるか」
を特定することです。

既存の設計を尊重し、不要なリファクタリングやアーキテクチャ変更は想定しないでください。

# 入力

以下のファイルを参照してください。

* PROJECT_MAP.md
* ARCHITECTURE.md
* repomix-compressed.xml

# 今回の要求

＜ここに変更したい内容を書く＞

# 調査してください

以下を特定してください。

1. 直接変更が必要と思われるファイル
2. そのファイル内のクラス・関数・メソッド
3. 変更によって影響を受ける可能性がある呼び出し元
4. Backend / Frontend間の影響
5. API仕様への影響
6. DBへの影響
7. 関連するテスト
8. 見落とすと問題になりそうな関連箇所

# 出力形式

## 変更候補

* ファイル
* クラス / 関数
* 変更理由

## 間接的な影響

* ファイル
* 関係
* 確認すべき理由

## テスト

* 既存テスト
* 追加・変更が必要と思われるテスト

## 不確実な点

コード全体を見ても判断できない点があれば明示してください。

この段階では実装コードやdiffを生成しないでください。

---

# 10. GPT-5.6の回答から必要ファイルを選ぶ

例えばGPT-5.6が、

```text
変更候補

backend/service/OrderService.ts
backend/service/CancellationPolicy.ts
backend/controller/OrderController.ts

間接的影響

backend/job/BatchCancelJob.ts
frontend/order/OrderDetail.tsx
frontend/order/useOrder.ts

テスト

backend/service/OrderService.test.ts
backend/service/CancellationPolicy.test.ts
```

と返したとする。

このファイルだけを次のRepomixの対象にする。

---

# 11. 部分コード用Repomixを作る

例えば、

```bash
repomix \
  --include "backend/service/OrderService.ts,backend/service/CancellationPolicy.ts,backend/controller/OrderController.ts,backend/job/BatchCancelJob.ts,frontend/order/OrderDetail.tsx,frontend/order/useOrder.ts,backend/service/*.test.ts"
```

のようにする。

実際にはプロジェクト構成に合わせてパスを変更する。

ポイントは、

> **「LLMが変更するファイル」だけではなく、「影響を確認するファイル」も含める**

こと。

---

# 12. 2回目のGPT-5.6への入力

ここで、

```text
PROJECT_MAP.md
ARCHITECTURE.md
repomix-compressed.xml
部分コードのRepomix
```

を渡す。

そして、

# 目的

先ほどの影響範囲分析に基づいて、実際のコードを確認してください。

まだコード変更は行わないでください。

# 確認事項

1. 先ほど特定した影響範囲に漏れがないか
2. 呼び出し元に見落としがないか
3. BackendからFrontendへの影響がないか
4. API仕様への影響がないか
5. DBや永続化処理への影響がないか
6. 非同期処理、バッチ処理、イベント処理への影響がないか
7. 関連テストに漏れがないか

# 特に重要

「今回アップロードされたコードだけを見ると問題ない」
ではなく、

PROJECT_MAP.md
ARCHITECTURE.md
repomix-compressed.xml

と照合して、リポジトリ全体の構造を考慮してください。

追加で確認すべきファイルがある場合は、
ファイルパスと確認理由を列挙してください。

問題がなければ、

「実装対象として十分」

と明示してください。

この段階ではコードを変更しないでください。

---

# 13. 追加ファイルが必要なら取得する

GPT-5.6が、

> `BatchCancelJob.ts`も確認が必要

と言ったら、そのファイルを追加する。

ここで重要なのは、

**最初から全体を再アップロードしないこと。**

```text
30万token
 ↓
20ファイル
 ↓
22ファイル
```

のように段階的に増やす。

---

# 14. 実装

影響範囲が固まったら、実装用プロンプトに切り替える。

# 役割

あなたは既存システムの保守・改修を行うシニアソフトウェアエンジニアです。

# 今回の要求

＜変更内容＞

# 実装方針

先ほど確認した影響範囲を前提として実装してください。

以下を厳守してください。

1. 既存設計を可能な限り維持する
2. 変更範囲を最小限にする
3. 不要なリファクタリングを行わない
4. 既存APIを勝手に変更しない
5. DBスキーマを勝手に変更しない
6. 既存の命名規則・コーディング規約を維持する
7. 既存テストを壊さない
8. 必要なテストも修正・追加する
9. 推測で存在しないファイルやAPIを作らない

# 出力

以下の順番で回答してください。

## 1. 実装方針

3〜5項目程度で簡潔に説明してください。

## 2. 変更対象

変更したファイルを列挙してください。

## 3. Diff

変更箇所をdiff形式で示してください。

変更していないコードは原則として全文出力しないでください。

## 4. テスト

実行すべきテストと、その理由を示してください。

## 5. 残存リスク

今回の変更だけでは確認できない点があれば明示してください。

---

# 15. 「全文コードを出して」は禁止する

これがかなり重要です。

悪い指示：

```text
修正後のOrderService.tsを全文出してください。
```

良い指示：

```text
変更箇所だけdiffで示してください。
変更していないコードは出力しないでください。
```

入力トークンほどではないものの、**出力トークンも積み重なる**ので、既存コード修正ではdiff中心にする。

---

# 16. テスト失敗時の使い方

実装後にテストが失敗した場合も、**30万tokenのリポジトリを再アップロードしない。**

渡すもの：

```text
PROJECT_MAP.md
必要なソース
テスト結果
```

そして、

以下のテスト結果を解析してください。

# テスト結果

＜エラー・ログを貼り付ける＞

# 目的

今回変更したコードに起因する問題かどうかを判断してください。

# 確認

1. エラーの直接原因
2. 今回の変更との関係
3. 修正すべきファイル
4. 修正方法
5. 既存仕様を壊す可能性

まず原因を説明してください。

原因が特定できるまで、不要なコード変更案を大量に提示しないでください。

---

# 17. Git diffも積極的に使う

既存コードの修正では、GPT-5.6に現在の状態だけでなく、

```bash
git diff
```

を渡すのも有効。

例えば、

```text
変更前
↓
変更後
↓
git diff
```

を確認させる。

プロンプト：

以下のgit diffをレビューしてください。

目的はコードをさらに変更することではなく、
今回の変更が要求を満たしているか確認することです。

確認してください。

1. 要求に対して必要な変更が入っているか
2. 不要な変更が含まれていないか
3. 既存仕様を壊す可能性
4. Backend / Frontend間の不整合
5. API仕様の不整合
6. テスト不足
7. 見落としている影響範囲

問題がある場合のみ、
「問題 → 理由 → 推奨修正」
の順番で示してください。

問題がなければ「重大な問題なし」としてください。

不要なリファクタリング案は提示しないでください。

---

# 18. 履歴数の設定

LLM Chat UIに「参照履歴数」の設定があるなら、**履歴を多くすればするほど良い、とは考えない。**

今回のようなコード修正では、

### 新しいタスク

```text
履歴：少なめ
```

から始める。

### 同じタスクを継続

```text
直近の必要な履歴を維持
```

### 複雑な修正

```text
過去の設計判断が重要なら増やす
```

とする。

特に、

> 新しい質問なのに過去20〜30ターンを毎回読ませる

という使い方は避ける。

---

# 19. 思考度合いの使い分け

LLM UIに「思考度合い」の設定があるなら、これも固定しない。

| 作業                 | 思考          |
| ------------------ | ----------- |
| 単純な typo 修正        | Low         |
| 単純な条件変更            | Low〜Medium  |
| 既存Service修正        | Medium      |
| 複数モジュール変更          | Medium〜High |
| Backend + Frontend | High        |
| 複雑なバグ調査            | High        |
| アーキテクチャ変更          | High        |

今回の方法では、

> **最初の影響範囲分析だけ思考度合いを高める**

という使い方もできます。

---

# 20. 出力詳細の設定

基本は低めにする。

例えば、

```text
調査：
出力詳細 Low〜Medium

実装：
Medium

コードレビュー：
Low〜Medium
```

とする。

特に、

> 「詳しく説明してください」

は避ける。

代わりに、

> 「変更理由を各ファイル1〜2行で」

などと指定する。

---

# 21. 1回の会話で全部やらない

今回の運用では、会話を以下のように区切るとよい。

```text
会話A
「影響範囲調査」

    ↓

会話B
「実装」

    ↓

会話C
「テスト失敗解析」

    ↓

会話D
「最終diffレビュー」
```

ただし、LLM UIの履歴参照が強力な場合は、同一会話で続けてもよい。

重要なのは、

**不要な過去履歴まで毎回GPT-5.6に読ませないこと。**

---

# 22. 使い分けの全体像

最終的には、以下のルールにする。

```text
┌────────────────────────────┐
│        変更要求             │
└─────────────┬──────────────┘
              ↓
      PROJECT_MAP.md
      ARCHITECTURE.md
      compressed Repomix
              ↓
        【調査Prompt】
              ↓
       影響範囲を特定
              ↓
       必要ファイルだけ
        Repomixで抽出
              ↓
        【確認Prompt】
              ↓
        影響範囲を再確認
              ↓
        【実装Prompt】
              ↓
             diff
              ↓
        compile / test
              ↓
        【レビューPrompt】
```

---

# 23. 「30万tokensを使ってはいけない」というルールにはしない

ここも重要。

大規模な変更では、

> 「全体を見た方がいい」

ケースがあります。

例えば、

* 認証方式変更
* DB schema変更
* API仕様の大規模変更
* 大規模リファクタリング
* Frontend / Backend共通仕様変更
* 複数サービスにまたがる変更

なら、圧縮版や広いコンテキストを使う。

したがってルールは、

> **「常に部分コード」ではなく、「必要なコンテキストだけ与える」**

です。

---

# 24. まず試すべき最小構成

いきなり複雑な仕組みを作らなくていいです。

まず各プロジェクトに、

```text
PROJECT_MAP.md
ARCHITECTURE.md
```

を作り、

```bash
repomix --compress
```

で圧縮版を作る。

そして、

**① 影響範囲分析
→ ② 対象コード抽出
→ ③ 実装**

の3段階にする。

これだけでも、現在の

```text
300K
 ↓
GPT-5.6
 ↓
毎回全部読む
```

から、

```text
10〜50K程度
 ↓
GPT-5.6
 ↓
必要なところだけ読む
```

へ移行できる可能性があります。

---

## 25. 最後に：LLM管理者に確認する項目

利用者側の工夫と並行して、管理者には次の4点を確認することをおすすめします。

```text
1. GPT-5.6 APIの cached_tokens は取得できるか？

2. 30万tokenのRepomixを同じ会話で繰り返し送った場合、
   Prompt Cacheは実際に効いているか？

3. Chat UIでは会話履歴と添付ファイルを
   APIにどのような順番で投入しているか？

4. 月額利用上限の計算では、
   cached input tokens と通常input tokensを
   別料金として扱っているか？
```

特に**4番目**は重要です。

今回「入力が料金の80%」という観測があるので、実際に

```text
input tokens
cached input tokens
output tokens
reasoning tokens
```

のどれが費用の大部分を占めているのか確認できれば、今回の運用改善の効果をかなり正確に予測できます。

**このマニュアルの核心は「Repomixを小さくすること」ではなく、「全体構造の把握」と「実コードの読解」を分離することです。** これなら「部分コードだけ渡したら影響範囲が分からない」という問題を維持しながら、30万tokenを毎回投入する必要をかなり減らせます。
