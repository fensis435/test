良い発見です。これは実装バグです。`src/config/env.ts`が`.env`ファイルを読み込む処理を一切持っておらず、`process.env`を直接参照しているだけでした。Prisma CLIは独自に`.env`を自動読込しますが、`tsx`で直接起動するこのアプリ自体にはその機能がありません。実際に動作するか検証します。`.env`が正しく読み込まれ、バリデーションを通過することを実機で確認しました。後片付けをしてZIPを再生成します。SETUP.mdのトラブルシューティング表にも今回の事象を追記します。`.env`は同梱されず(意図通り)、修正済みの`env.ts`と`package.json`は含まれています。# 原因と修正

## 原因(実装バグ)
`src/config/env.ts`は`process.env`をzodで検証するだけで、**`.env`ファイルを`process.env`に読み込む処理そのものが存在していませんでした**。

- `npx prisma migrate dev`が動いていたのは、**Prisma CLIが独自に`.env`を自動読込する**機能を持っているためです(ログに`Environment variables loaded from .env`と出ていたのはPrismaの機能であり、このアプリ自体の機能ではありませんでした)。
- 一方`npm run dev`(`tsx watch src/server.ts`)は素のNode.js実行であり、dotenv相当の処理を挟まない限り`.env`の中身は`process.env`に一切反映されません。

これは前回・前々回の私の実装ミスです。「`.env`さえ作ればPrisma同様に読まれるはず」という誤った前提でコードを書いていました。

## 修正内容

| ファイル | 内容 |
|---|---|
| `package.json` | `dotenv`パッケージを依存関係に追加 |
| `src/config/env.ts` | 先頭で`loadDotenv()`(dotenvの`config()`)を呼び出し、`.env`を`process.env`に反映してからzod検証するよう修正。エラー時のヒントメッセージも追加 |
| `SETUP.md` | トラブルシューティング表に本事象を追記 |

## 実機検証済み
実際に`dotenv`をインストールし、一時的な`.env`ファイルを用意して`env.ts`をimportし、`OIDC_ISSUER`等が正しく`process.env`経由で読み込まれることを確認しました(検証後、テスト用ファイルは削除済みです)。

## 再実行手順

```bash
npm install   # dotenvが追加されます
npm run dev
```

`.env`の中身は変更不要です(前回作成いただいたものがそのまま使えます)。それでも起こる場合は、`.env`が`oidc-dev-server`ディレクトリ直下(`package.json`と同じ階層)にあるかご確認ください。