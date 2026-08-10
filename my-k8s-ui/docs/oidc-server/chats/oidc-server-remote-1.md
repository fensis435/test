## 1. `http://`ではなく`https://`にする必要があります

`mkcert` + `Caddy`でTLS終端する構成にした以上、ブラウザから見えるオリジンは`https://idp.dev.test`です。`http://`のままだと、ブラウザは実際には`https`でCaddyにアクセスしているのに、`oidc-client-ts`が構築するリダイレクトURLやDiscoveryへのfetch先が`http`になってしまい、混在(mixed content)や`iss`不一致でエラーになります。

```
VITE_OIDC_ISSUER=https://idp.dev.test
```

## 2. 末尾のスラッシュは付けない

```
VITE_OIDC_ISSUER=https://idp.dev.test/   ← 避ける
VITE_OIDC_ISSUER=https://idp.dev.test    ← これが正しい
```

`oidc-provider`は内部で`issuer + "/.well-known/openid-configuration"`のように単純結合してURLを組み立てます。末尾にスラッシュがあると`https://idp.dev.test//.well-known/...`のような二重スラッシュになり、正規化に依存した挙動になってしまいます。またDiscoveryドキュメント内の`issuer`フィールドとの厳密一致検証で不整合が起きる可能性もあるため、末尾スラッシュなしが標準です。

## 重要:3つのアプリすべてで一致させる必要があります

`VITE_OIDC_ISSUER`(フロントエンド)だけでなく、**`oidc-dev-server`自身の`.env`の`OIDC_ISSUER`も同じ値に変更されている必要があります**。ここが一番見落としやすい落とし穴です。

`oidc-dev-server`側の`OIDC_ISSUER`は、単なる「フロントエンドが接続する先」ではなく、**JWKSやすべてのトークンの`iss`クレームそのものに焼き込まれる、このIdPの「アイデンティティ」**です。もしここが`http://localhost:3000`のままだと、

- Discoveryドキュメントの`issuer`フィールドが`http://localhost:3000`のまま返る
- 発行されるID Token/Access Tokenの`iss`クレームも`http://localhost:3000`のまま
- フロントエンド(`https://idp.dev.test`宛にリクエストしている)側の`oidc-client-ts`が、レスポンスの`issuer`と自分が期待している`authority`の不一致を検知してエラーにする

という形で、今回とは別の新しいエラーに変わるだけになります。

まとめると、3箇所すべてを揃える必要があります。

| アプリ | 変数 | 値 |
|---|---|---|
| `oidc-dev-server` | `OIDC_ISSUER` | `https://idp.dev.test` |
| React(frontend) | `VITE_OIDC_ISSUER` | `https://idp.dev.test` |
| Rails(backend) | `OIDC_ISSUER` | `https://idp.dev.test` |

`oidc-dev-server`の`.env`を変更した後は、当然`npm run dev`の再起動も必要です。合わせて`OIDC_TRUST_PROXY=true`も設定済みか、この機会に確認してください(これが無いとCookieの`Secure`属性が正しく付かず、別の症状で詰まる可能性があります)。
