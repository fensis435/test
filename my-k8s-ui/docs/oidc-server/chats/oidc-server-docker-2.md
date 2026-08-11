## 原因

`oidc-dev-server`サービス(`target: runtime`)は非rootユーザー(`appuser`, uid 1001)で動作しますが、先ほど追加した`jwks`サービス(`target: build`)には`USER`指定がなく**rootで実行されます**。

`generate-jwks.ts`は秘密鍵ファイルを`mode: 0o600`(所有者のみ読み書き可)で書き込むため、rootが生成した`jwks.json`は**root以外読めません**。結果として、後から起動する非root(uid 1001)の`oidc-dev-server`コンテナが読めずに`EACCES`になっています。

`jwks`サービスに`appuser`と同じuid/gidを指定して実行させることで解消します。`uid=1001, gid=1001`であることを確認しました。`jwks`サービスに同じユーザーを明示します。YAML構文を検証します。`migrate`/`seed`サービスにも**全く同じ潜在バグ**があることに気づきました。両方とも`root`権限で`/data`ボリュームに書き込むため、SQLiteのDBファイルがroot所有になり、後から起動する非rootの`oidc-dev-server`が書き込めなくなる可能性があります。次のエラーとして表面化する前に、同時に修正します。YAML構文と全体の整合性を最終確認します。`jwks`・`migrate`・`seed`の3サービスすべてに反映されています。SETUP.mdのトラブルシューティング表にも追記します。ZIPを再生成します。# 原因と修正

## 原因

`jwks`サービス(`target: build`イメージ)には`USER`指定がなく**root権限で実行**されます。`generate-jwks.ts`は秘密鍵ファイルを`mode: 0o600`(所有者のみ読み書き可)で書き込むため、root所有の`jwks.json`が生成されました。

一方`oidc-dev-server`サービス(`target: runtime`)は非rootユーザー(`appuser`, uid 1001)で動作するため、rootが0600で作った鍵ファイルを読めず`EACCES`になっていました。

`migrate`/`seed`サービスにも同じ構造の潜在バグがある(SQLiteのDBファイルがroot所有になり、後で非rootの`oidc-dev-server`が書き込めなくなる)ことに気づいたため、3サービス同時に修正しています。

## 修正内容

`jwks`・`migrate`・`seed`の3サービスすべてに`user: "1001:1001"`(runtimeコンテナの`appuser`と同じuid/gid)を明示的に指定しました。

## 【重要】お手元での対応手順

**既に一度`docker compose --profile jwks run`を実行済みのため、ボリューム内にroot所有の古いファイルが残っています。** 単に修正版で再実行しても、`generate-jwks.ts`は「既にファイルが存在する場合は上書きしない」実装のため、古い(読めない)ファイルがそのまま残ってしまいます。

ボリュームを一度削除してからやり直してください。

```bash
docker compose down -v
```

その後、改めて①からやり直します。

```bash
docker compose build
docker compose --profile jwks run --rm jwks
docker compose --profile migrate run --rm migrate
docker compose --profile seed run --rm seed
docker compose up -d oidc-dev-server
```

`docker compose down -v`は`oidc-data`ボリューム(DB)も削除するため、既に作成済みのユーザー等があれば失われます。再度シード投入が必要です。
