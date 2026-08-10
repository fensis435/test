根本原因が確定的に特定できたので、診断用ログを削除してクリーンな状態に戻します。診断ログを削除し、クリーンな実装に戻します。`interactions.ts`の診断ログも削除します。診断ログが完全に除去されたか横断確認します。全て除去されました。構文チェックを行います。`resource`フィールドが両strategyに正しく組み込まれたか横断確認します。`AuthorizationCode`・`RefreshToken`両方の`upsert`/`find`に反映されています。SETUP.mdを更新し、後片付けとZIP再生成を行います。# 修正完了

診断ログのおかげで、`useGrantedResource`のログが一度も出ていないという決定的な手がかりが得られました。これを起点にoidc-provider本体のソース(`resolve_resource.js`、`authorization_code.js`)を追い、`adapter.ts`に`resource`フィールドの扱いが**一切存在しない**ことを`grep`で確認し、確定的な原因特定に至りました。

## 根本原因(3段目)

これで判明した全体像は以下の通りです。

1. `formats: { AccessToken: "jwt" }` → 存在しない設定キー(修正済み)
2. `resourceIndicators`を正しく設定 → `/authorize`側は完璧に動作(ログで確認済み)
3. **しかし`/token`交換時、`AuthorizationCode`から復元される`code.resource`が`undefined`だった**

`adapter.ts`の`authorizationCodeStrategy`と`refreshTokenStrategy`は、Prismaの手動組み立てpayloadに`resource`フィールドを一切含めていませんでした。これは前回・前々回の`grantId`・`jti`と**全く同じ「手動payload再構築での特定フィールド欠落」パターン**です。

`resolve_resource.js`の`switch(true)`ロジックは`!model.resource`を最初に評価するため、`code.resource`が`undefined`だと即座に「resourceなし」と判定し、`useGrantedResource`にすら到達せずAccess Tokenがopaqueのまま発行されていました。

## 修正内容

| ファイル | 内容 |
|---|---|
| `prisma/schema.prisma` | `AuthorizationCode`と`RefreshToken`の両方に`resource String?`カラムを追加 |
| `src/oidc-core/adapter.ts` | 両strategyの`upsert`/`find`で`resource`を正しく保存・返却するよう修正 |
| `src/oidc-core/provider.ts` / `interactions.ts` | 診断用の`[DEBUG]`ログをすべて削除(機能修正部分は維持) |
| `SETUP.md` | 今回の事象を追記 |

## お手元での実行手順(マイグレーション必須)

```bash
npx prisma migrate dev --name add_resource_indicator_fields
npx prisma generate
npm run dev
```

その後、ログアウト→再ログインして「Rails APIを呼ぶ」をお試しください。今度こそAccess TokenがJWT形式(3セグメント)で発行され、Rails側の検証が通るはずです。

## 検証状況

`adapter.ts`の全`resource`関連コードは静的に確認済み(grepで両strategyに反映されていることを確認)。構文チェックも全ファイルOKです。ただしこれまで同様、このサンドボックスでのPrisma実機起動によるE2E確認はできていません。

もしまだ何か出るようであれば、今回`resource`が正しく機能した場合に次に怪しいのは`RefreshToken`テーブル(Refresh Token Grant利用時)ですが、これも今回同時に修正済みです。
