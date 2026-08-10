## 原因1(WARNING):`OIDC_TRUST_PROXY`が設定されていない

```
oidc-provider WARNING: x-forwarded-proto header detected but not trusted, you must set proxy=true on the provider.
```

Caddyが`X-Forwarded-Proto: https`ヘッダを送ってきているのに、`.env`の`OIDC_TRUST_PROXY`が`true`になっていません。前回お伝えした確認事項がまだ反映されていない状態です。

```bash
# oidc-dev-server の .env
OIDC_TRUST_PROXY=true
```

これはWARNINGなので即座にエラーにはなっていませんが、放置するとCookieの`Secure`属性が正しく付与されない別の問題を後で引き起こします。必ず直してください。

## 原因2(本命のエラー):Clientの`redirectUris`が新ドメインで再登録されていない

```
error: 'invalid_redirect_uri',
error_description: "redirect_uri did not match any of the client's registered redirect_uris"
```

これは`LOCAL_HTTPS_SETUP.md`の**手順⑤(Clientの再登録)**がまだ実施されていません。`react-web-test-client`は、まだ`http://localhost:5173/callback`で登録されたままのはずです。ブラウザは新ドメイン`https://app.dev.test/callback`宛にリクエストしていますが、oidc-provider側に登録された値と一致せず拒否されています。

Clientを新ドメインで登録し直してください。

```bash
ruby scripts/register_client.rb \
  --issuer https://idp.dev.test \
  --admin-email admin@example.com \
  --admin-password change-me-please \
  --redirect-uri https://app.dev.test/callback
```

**注意点**: `register_client.rb`はデフォルトで`--client-id react-web-test-client`を使うため、同じclient_idで既に登録済みだと**409(スキップ)**になり、`redirectUris`は更新されません。以下のいずれかで対応してください。

**選択肢A: 別のclient_idで新規登録する(お手軽)**

```bash
ruby scripts/register_client.rb \
  --issuer https://idp.dev.test \
  --admin-email admin@example.com \
  --admin-password change-me-please \
  --client-id react-web-test-client-https \
  --redirect-uri https://app.dev.test/callback
```

この場合、`frontend/.env`の`VITE_OIDC_CLIENT_ID`もこの新しいIDに変更してください。

**選択肢B: 既存Clientの`redirectUris`をPATCHで更新する**

```bash
# 1. 管理者ログイン
curl -s -X POST https://idp.dev.test/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"admin@example.com","password":"change-me-please"}' | tee /tmp/login.json

# 2. accessTokenを使ってredirectUrisを更新
ACCESS_TOKEN=$(node -e "console.log(require('/tmp/login.json').accessToken)")

curl -s -X PATCH https://idp.dev.test/api/v1/clients/react-web-test-client \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -d '{
    "redirectUris": ["https://app.dev.test/callback"],
    "postLogoutRedirectUris": ["https://app.dev.test/"]
  }'
```

選択肢Bの方が、既存のclient_idをそのまま使い続けられるので手戻りが少なくおすすめです。

---

`OIDC_TRUST_PROXY=true`の設定 → `oidc-dev-server`再起動 → 上記どちらかでClient更新、の順で試してみてください。
