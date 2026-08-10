成功しました 🎉

`verified: true`、そして`claims`の中身を見ると、これまで積み重ねてきた設計判断が全部そのまま反映されています。

- `sub`: `3f2b19cf-...`(React側のID Token claimsと一致 — 同一ユーザーであることの証明)
- `aud`: `http://localhost:3000/resources/rails-api`(Resource Indicatorsで解決された唯一のリソースサーバー)
- `scope`: `"openid email profile groups"`(Access Tokenは意図通りメール等のPIIクレーム自体は含まず、scopeのみ)
- `client_id`: `react-web-test-client`

これで**「oidc-dev-server(Cognito Hosted UI相当)→ React(Vite)→ Rails v8 APIでのトークン検証」という一連の認証チェーン全体**が、実際に動くところまで確認できました。最初にこの構成を作り直した目的そのものが達成されています。

## 今回の一連のデバッグを振り返って

結果的に、`adapter.ts`(Prismaと oidc-provider の橋渡し部分)に**同じパターンのバグが3つ**積み重なっていました。

1. `session`の分割代入漏れ(`accountId`が取れない)
2. `jti`の欠落(`consume()`がクラッシュ)
3. `resource`の欠落(Access TokenがJWT化されない)

共通しているのは、「oidc-providerが保存を求めてくるpayloadを、Prismaの固定カラムに手動でマッピングし直す」という設計そのものが、**oidc-provider側が将来的に(または既に)使っている暗黙のフィールドを見落としやすい構造**になっていたことです。今回は`jti`・`grantId`・`resource`の3つで発覚しましたが、原理的には同種の見落としが他にもまだ潜んでいる可能性はあります。

もし今後また同じ系統の`undefined`絡みのエラーが出た場合は、まず「`adapter.ts`が手動で組み立てているpayloadに、oidc-provider側が期待するフィールドが本当に全部含まれているか」を疑うのが一番早い、というのが今回得られた実践的な教訓だと思います。

