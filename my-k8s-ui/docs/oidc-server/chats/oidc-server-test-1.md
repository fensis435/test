理解しました。これまでのRuby(Sinatra)単体クライアントは、実際のターゲット構成(React+Vite / Rails v8)を反映していませんでした。本来の目的である「Cognito Hosted UI相当 → React → Railsバックエンドでのトークン検証」という一連の鎖を、最小構成のトップページだけで検証できる形に作り直します。

まず既存のRuby単体クライアントの位置づけを整理し、新構成に置き換えます。## 1. React + Vite フロントエンド`auth.ts`(oidc-client-ts設定、ログアウトの「ラッパー」パターン)を作成します。App.tsx(検証専用トップページ)を作成します。npmで実際にインストール・ビルドして検証します。`.env`を用意してビルド検証します。ビルド成功、型エラーなしです。後片付けをします。## 2. Rails v8 バックエンド(トークン検証専用)

`rails new`は実行できない(gemインストールにネットワーク制限あり)ため、Rails 8のAPIモード規約に沿って手書きします。**Active Record等、トークン検証に不要なコンポーネントは意図的に含めません。**OIDC issuer設定とCORS設定を追加します。TokenVerifierサービス(JWKS経由のJWT検証)を作成します。コントローラとルーティングを作成します。Puma設定・config.ru・bin/railsを作成します。`.env.example`とREADMEを作成します。直前のNode.jsプロジェクトで学んだ教訓を踏まえます。Railsも`.env`を自動読込しないため、`dotenv-rails`を明示的に追加します。READMEを作成します。Ruby構文を全ファイル検証します。`jwt`gemがインストールできない(前回と同じネットワーク制約)ため、構文チェックまでが本サンドボックスでの検証限界です。次にReactクライアント登録スクリプトと全体READMEを作成します。全体を統括するREADMEを作成します。.gitignoreを追加し、最終検証・ZIP化します。ビルド時の副産物(`.tsbuildinfo`、`vite.config.js`等)を除外してZIP化します。# テストコードを本来の目的に沿って書き直しました

前回のRuby(Sinatra)単体クライアントは、実際のターゲットスタックを反映していませんでした。今回は「oidc-dev-server(Cognito Hosted UI相当)→ React(Vite)→ Rails v8バックエンドでのトークン検証」という一連の鎖を、**最小構成のトップページ1枚だけ**で検証できる形に作り直しています。

## 構成

```
oidc-web-test/
├── frontend/   React + Vite(oidc-client-ts)。トップページのみ
├── backend/    Rails v8 API。Access Token検証専用(ActiveRecord等は含まない)
└── scripts/    Reactクライアントの自動登録スクリプト
```

## トップページの動作(要件通りの最小構成)

1. 「ログイン」ボタン → Authorization Code + PKCE
2. コールバック後、ID Token claimsを表示
3. **「Rails APIを呼ぶ」ボタン** → Access TokenをBearerとしてRails v8 APIに送信し、Rails側がJWKS経由で署名検証した結果を画面に表示
4. 「ログアウト」ボタン

3番が成功して初めて「バックエンドでのトークン検証」まで含めた一連の鎖が確認できたことになります。それ以外の業務UIやルーティングは持たせていません。

## 設計上のポイント

- **Rails側は`rails/all`を使わず`action_controller`のみ読み込み**: ActiveRecord・ビュー・アセットパイプライン等、トークン検証に不要なものは意図的に排除しました。
- **`TokenVerifier`(Rails)・`auth.ts`のログアウト関数(React)にCognito差異吸収の設計をそのまま反映**: これまでの設計方針(issuer切替のみでの移行、ログアウトのみラッパーに差異を閉じ込める)を踏襲しています。

## 実機検証した内容

| 項目 | 結果 |
|---|---|
| React: `npm install` → `npm run build`(`tsc -b && vite build`) | ✅ 型エラー・ビルドエラーなし、実際にビルド成功を確認 |
| Rails: 全Rubyファイルの構文チェック(`ruby -c`) | ✅ 全ファイルOK |
| Rails: `bundle install`によるRails自体の起動確認 | ❌ 未実施(このサンドボックスは`rubygems.org`への接続が制限されているため、これまでのRuby関連の作業と同じ制約です) |

Railsバックエンドを`bin/rails server`で起動した際に何かエラーが出れば、これまでのやり取り同様、エラーメッセージを共有してください。実機で再現・修正します。

