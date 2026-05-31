# LLMを使ってソースコードを把握し、開発を進める流れ

以下に、ソースコードをアップロードしてから機能追加・修正指摘までの一連の会話例を示します。

---

## 前提：アップロード方法

**ファイル/フォルダのアップロード方法（いずれか）**

- **小〜中規模**：ファイルを直接チャットにドラッグ＆ドロップ（複数可）
- **中〜大規模**：ZIPで圧縮してアップロード → Claudeが展開して読む
- **大規模**：リポジトリをZIPでダウンロードしてアップロード（GitHubなら `Code > Download ZIP`）

---

## 一連の会話例

---

### 💬 Step 1｜全体把握（最初の一手）

> **あなた：**
> `my-app.zip` をアップロードしました。
>
> このソースコードの全体像を把握したいです。以下を教えてください。
> 1. このソフトウェアは何をするものか（3行以内で）
> 2. 技術スタック（言語・フレームワーク・主要ライブラリ）
> 3. ディレクトリ構成と各フォルダの役割
> 4. アプリケーションのエントリーポイント

> **Claude：**
> ZIPを展開して確認しました。
>
> 1. **概要**：ECサイトのバックエンドAPI。商品管理・注文処理・ユーザー認証を提供するREST API。
> 2. **技術スタック**：Node.js / Express / TypeScript、DB は PostgreSQL（Prisma ORM）、認証はJWT
> 3. **ディレクトリ構成**：
>    - `src/routes/` … エンドポイント定義
>    - `src/services/` … ビジネスロジック
>    - `src/models/` … Prismaスキーマ
>    - `src/middleware/` … 認証・バリデーション
> 4. **エントリーポイント**：`src/index.ts`

---

### 💬 Step 2｜機能・モジュールの詳細把握

> **あなた：**
> 主要な機能モジュールを一覧にして、それぞれの責務・主要なファイル・公開しているAPIエンドポイントをまとめた表を作ってください。

> **Claude：**
>
> | モジュール | 責務 | 主要ファイル | エンドポイント |
> |---|---|---|---|
> | 認証 | ログイン・JWT発行 | `auth.service.ts` | `POST /auth/login` |
> | 商品管理 | CRUD・在庫管理 | `product.service.ts` | `GET/POST /products` |
> | 注文処理 | 注文作成・ステータス管理 | `order.service.ts` | `POST /orders` |
> | ユーザー | プロフィール管理 | `user.service.ts` | `GET /users/:id` |

---

### 💬 Step 3｜データモデルの把握

> **あなた：**
> データモデル（テーブル・エンティティ）の関係を説明してください。ER図的なテキスト表現でもいいです。主要なフィールドと、テーブル間のリレーションを含めてください。

> **Claude：**
> ```
> User (1) ──< Order (多)
> Order (1) ──< OrderItem (多)
> OrderItem >── Product (1)
> Product >── Category (1)
> ```
> - `User`：id, email, passwordHash, role(admin/customer)
> - `Order`：id, userId, status(pending/paid/shipped), totalAmount
> - `OrderItem`：id, orderId, productId, quantity, unitPrice
> - `Product`：id, name, price, stock, categoryId

---

### 💬 Step 4｜問題点・技術的負債の洗い出し

> **あなた：**
> コードを読んで、以下の観点で問題点や改善すべき点を指摘してください。
> - セキュリティリスク
> - パフォーマンス上の懸念
> - コードの保守性・設計上の問題
> - テストの欠如

> **Claude：**
>
> **🔴 セキュリティ**
> - `order.service.ts:45`：SQLクエリを文字列結合で組み立てている（SQLインジェクションリスク）→ Prismaのパラメータ化クエリに置き換えるべき
> - パスワードリセットトークンの有効期限が未設定
>
> **🟡 パフォーマンス**
> - 注文一覧取得でN+1問題が発生（ループ内でUserを個別取得）→ `include`でJOINすべき
> - 商品検索にインデックスなし
>
> **🟠 保守性**
> - `index.ts`が500行超でルーティング・ミドルウェア・起動処理が混在
> - エラーハンドリングが各ルートに散在、共通ミドルウェア化すべき
>
> **⚪ テスト**
> - テストファイルが皆無。最低限、`auth.service`と`order.service`の単体テストが必要

---

### 💬 Step 5｜特定の機能追加を相談

> **あなた：**
> このシステムに「クーポン機能」を追加したい。既存のコードのどこに何を追加・変更すれば実現できるか、影響範囲と実装方針を教えてください。

> **Claude：**
>
> **影響範囲と実装方針：**
>
> 1. **新規テーブル** `Coupon`：code, discountType(rate/fixed), discountValue, expiresAt, usageLimit
> 2. **変更：`order.service.ts`** の注文作成ロジックにクーポン検証・割引計算を追加
> 3. **変更：`Order`テーブル** に `couponId`（nullable FK）と `discountAmount` カラムを追加
> 4. **新規エンドポイント** `POST /coupons/validate`（フロントの入力チェック用）
> 5. **既存テスト**への影響：注文作成のテストケースにクーポンあり/なしのケース追加が必要
>
> まず `prisma/schema.prisma` にCouponモデルを追加してマイグレーションを作成し、次にサービス層の修正に進むのが安全です。実装コードを書きますか？

---

### 💬 Step 6｜具体的な修正コードを生成

> **あなた：**
> Step 4で指摘されたN+1問題を修正してください。該当箇所の修正前・修正後のコードを示してください。

> **Claude：**
>
> **修正前（`order.service.ts:78`）：**
> ```typescript
> const orders = await prisma.order.findMany();
> for (const order of orders) {
>   order.user = await prisma.user.findUnique({ where: { id: order.userId } });
> }
> ```
>
> **修正後：**
> ```typescript
> const orders = await prisma.order.findMany({
>   include: { user: true, items: { include: { product: true } } }
> });
> ```
> これでDBへのクエリ回数が O(N) → O(1) になります。

---

## まとめ：プロンプトの進め方

```
① 全体把握（概要・技術スタック・構成）
      ↓
② 機能・API一覧の表形式整理
      ↓
③ データモデル・依存関係の可視化
      ↓
④ 問題点・技術負債の洗い出し
      ↓
⑤ 特定機能の追加・変更の影響範囲確認
      ↓
⑥ 具体的な修正コード生成
```

**コツ：**
- 一度に全部聞かず、段階的に深掘りする
- 「〇〇ファイルの△△関数を詳しく説明して」と局所的に深掘りできる
- 「この変更の影響範囲は？」と安全性を確認してから実装へ進む
- 大規模コードの場合は「認証モジュールだけ先に詳しく教えて」と分割して把握する
