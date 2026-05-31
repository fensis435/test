まず結論から言うと、

> AI専用ナレッジベースは非常に有効だが、コードそのものを入力した場合と同じ効果にはならない

が正確な答え。

---

## コード入力とナレッジベースの違い

例えば実際のコードが

```python
def calculate_discount(user, amount):
    if user.is_premium:
        return amount * 0.8

    if user.points > 1000:
        return amount * 0.9

    return amount
```

だとする。

ナレッジベースには

```text
割引ルール

- Premium会員は20%割引
- ポイント1000超は10%割引
```

と書ける。

これは設計意図としては十分。

しかし、

* 実際の変数名
* 呼び出し箇所
* 副作用
* バグ
* エッジケース

までは残らない。

つまり

### ナレッジベースが得意

* システム理解
* 設計理解
* 機能理解
* 影響範囲推定

### コード本体が必要

* 実装修正
* リファクタリング
* バグ調査
* 正確なレビュー

---

## 実務での理想形

実は

```text
AI_CONTEXT.md
+
実際のコード検索
```

が最強。

最近のAI開発ツールもほぼこれ。

流れとしては

```text
AI_CONTEXT.md
↓
システム理解

必要な時だけ

user_service.py
auth_controller.rb
payment.ts
を取得
```

となる。

---

# 階層化プロンプト

大規模案件向け。

まずルート文書を作らせる。

---

### Phase1

```text
あなたはソフトウェアアーキテクトです。

コードベース全体を分析し、
AIが保守開発を行うための
ドキュメント体系を設計してください。

以下の成果物を作成してください。

1. AI_CONTEXT.md
2. PROJECT_OVERVIEW.md
3. ARCHITECTURE.md
4. DATABASE.md
5. API.md
6. AUTH.md
7. FRONTEND.md
8. BACKEND.md
9. DEPLOYMENT.md
10. TROUBLESHOOTING.md

まず各ドキュメントの役割を定義してください。

内容の重複は避け、
参照関係を明示してください。
```

---

次に個別文書を作る。

---

### Phase2

```text
ARCHITECTURE.mdを作成してください。

対象読者は
このコードベースを知らない別のLLMです。

以下を記載してください。

- システム全体図
- レイヤー構成
- モジュール一覧
- モジュール依存関係
- データフロー
- イベントフロー
- 外部サービス連携
- 設計パターン

実装詳細ではなく
アーキテクチャ理解を目的としてください。
```

---

### DATABASE.md用

```text
データベース構造を分析し
DATABASE.mdを生成してください。

記載内容:

- ER構造
- 主要テーブル
- 主キー
- 外部キー
- インデックス
- 重要な制約
- ビジネスルール

実際のSQLではなく
概念レベルで説明してください。
```

---

### API.md用

```text
全APIを分析し
API.mdを生成してください。

各APIについて

- Endpoint
- Method
- Purpose
- Request
- Response
- Authentication
- Related Services

を記載してください。

細かな型情報は省略し
設計理解を優先してください。
```

---

## 個人的に一番効果が高い文書

意外かもしれないけど、

```text
DANGEROUS_AREAS.md
```

が非常に強い。

プロンプト例：

```text
コードベースを分析し
DANGEROUS_AREAS.mdを作成してください。

記載内容:

- 修正時に壊れやすい箇所
- 密結合な箇所
- 暗黙の依存関係
- 技術的負債
- テスト不足領域
- 過去に障害が起きそうな箇所

後続LLMが
安全に改修できるよう
重点的に記述してください。
```

---

## 「コード入力と同等」に近づける方法

ナレッジベースだけだと60〜80%くらいの理解度になることが多い。

そこでさらに、

```text
AI_CONTEXT.md
ARCHITECTURE.md
DATABASE.md
API.md
DANGEROUS_AREAS.md
```

に加えて、

```text
MODULE_INDEX.md
```

を作る。

例えば

```text
UserService

責務:
ユーザー管理

主要メソッド:
create_user
update_user
delete_user

依存:
UserRepository
EmailService

呼び出し元:
UserController
AdminController

関連DB:
users
profiles
```

のように、主要クラス・サービス・モジュールの索引を作る。

これがあると、高性能モデルは

> UserService を確認したいので関連ファイルだけ見せて

という動きができる。

実務感覚だと、

* コード全文 = 100%
* 良質なAIナレッジベース + 必要時コード参照 = 85〜95%
* 要約だけ = 30〜60%

くらいの差になることが多い。だから「コード全文の代替」を目指すより、「高性能モデルが必要なコードを素早く見つけられる地図を作る」という発想の方が成功しやすい。
