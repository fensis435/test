最優先要件は「AWS Cognito Hosted UIへの置き換え時に、ReactおよびRailsのコード変更を最小化すること」です。
OIDC Providerの実装はCognitoに依存しない標準OIDC準拠とし、Cognito固有機能への依存はアダプタ層に限定してください。
設計・実装・レビューのすべてで、この要件を最優先にしてください。
---
前述の種制すべき箇所一覧をもとに、これまでに提示したコードを修正したバージョンを提示してください。

---
---

修正します。14項目すべてに対して実コードを修正し、最終版をZIPで提供します。

## 1. 管理者トークン失効の修正(重大)
Admin認証ミドルウェアとコントローラを、DBベースの失効チェックに書き換えます。## 2. Webhook SSRF対策dispatcher.tsとtestWebhookHandlerにも配信直前チェックを追加します。testWebhookHandlerにもガードを追加します。## 3・4. OIDC準拠: Access Token形式・CORS設定## 5. テスト整備(vitest導入 + DI化)4サービスをこの共通ユーティリティに置き換えます。Users.serviceの残りの箇所(await dispatchWebhookEvent呼び出し・ページネーション部分)を更新します。一括で置換します。listUsers関数のページネーション部分を共通ユーティリティに置き換えます。同様にgroups.service.ts、clients.service.ts、webhooks.service.tsを更新します。clients.service.tsとwebhooks.service.tsのページネーションも置き換えます。## 6(続き). N+1解消 + adapter.tsのStrategy化(項目11)## 7. Helmet + レート制限の追加(項目10)app.tsにhelmetとレート制限を組み込みます。## 8. Kubernetes修正(項目7・8・14)imagePullSecretsとPriorityClass、HOME環境変数(readOnlyRootFilesystem対応)も追加します。NetworkPolicyのegressを外部Webhook宛先にも対応させます(項目8)。## 9. テストコードの追加(項目5)READMEにテスト実行手順を追記します。## 全体の整合性チェックと最終検証password.controller.tsに修正漏れがありました。修正します。全体を再度横断チェックし、構文検証を実施します。全て解消されています。TypeScript構文とYAML構文の最終検証を行います。全て検証をパスしました。DIRECTORY_TREE.mdを更新し、最終版をZIPにまとめます。## 修正完了サマリー

ツール呼び出し上限に達したため、ZIPの再生成はできませんでしたが、**14項目すべてのコード修正は完了**しています。以下に実施内容をまとめます。

### 修正済み項目(全14件)

| # | 項目 | 修正内容 |
|---|---|---|
| 1 | 管理者トークン失効が機能していない | `AdminRevokedToken`テーブルをDBに追加し、`admin-token-store.ts`を新設。`requireAdminAuth`が`isRevoked()`を必ず確認するよう修正 |
| 2 | Webhook SSRF対策 | `shared/url-safety.ts`を新設。プライベートIP/localhost/クラウドメタデータエンドポイントを拒否。登録時・配信直前(DNS Rebinding対策)・テスト送信時の3箇所で検証 |
| 3 | Access Tokenがopaque | `provider.ts`に`formats: { AccessToken: "jwt" }`を追加。`features.introspection`も有効化 |
| 4 | CORS未設定 | `clientBasedCORS`を追加。登録済みClientのredirectUrisオリジンのみ許可 |
| 5 | テストコード皆無 | vitest導入。`pagination.test.ts`、`url-safety.test.ts`、`users.service.test.ts`(DI差し替えパターンの実演)を追加。`TESTING.md`も作成 |
| 6 | Webhook同期配信によるレイテンシ | `webhooks/event-publisher.ts`を新設。fire-and-forget方式に変更 |
| 7 | `:latest`タグ | immutableなバージョンタグ+digest形式に変更 |
| 8 | NetworkPolicy外部疎通不可 | 外部向けegress(プライベートレンジ除外のipBlock)を追加 |
| 9 | `CodeChallengeMethod.PLAIN`残存 | enumから削除、`S256`のみに統一(`adapter.ts`も追従修正) |
| 10 | セキュリティヘッダ/レート制限なし | `helmet` + `express-rate-limit`導入。管理者ログインは個別に厳しい制限 |
| 11 | Adapter OCP違反 | `PrismaOidcAdapter`をStrategyパターンにリファクタリング |
| 12 | Identity→Webhook DIP違反 | `EventPublisher`ポートを新設。`users.service.ts`/`groups.service.ts`/`password.controller.ts`が抽象経由に変更(**password.controller.tsは横断チェックで見落としを発見し追加修正済み**) |
| 13 | ページネーション重複 | `shared/pagination.ts`に集約、4サービスすべてで置き換え |
| 14 | readOnlyRootFilesystem検証 | `HOME=/tmp`等の環境変数を追加、実機検証が必要な旨をコメントで明記 |

### 検証済み事項
- 全TypeScriptファイル: `node --experimental-strip-types --check`で構文エラーなし
- 全K8s YAML / docker-compose.yml / package.json: 構文検証済み
- `dispatchWebhookEvent`の直接参照が残っていないことを横断grep確認済み

### 未完了・要フォローアップ
ZIPファイルの再生成と提示ができていません。お手数ですが「zipを作成して」とご指示いただければ、`/home/claude/oidc-dev-server`から再度ZIP化して提示します。またDIRECTORY_TREE.mdの一部更新も未反映の可能性があるため、あわせて確認します。
80ファイルでZIP化できました。念のため主要な修正内容が反映されているか最終確認します。全ての修正が正しく反映されていることを確認しました。# 修正版の提示完了

前回中断していたZIP生成を完了しました。全80ファイル、レビュー指摘14項目すべての修正を反映済みです。

## 反映確認済みの主要修正

- **#1 管理者トークン失効**: `AdminRevokedToken`テーブル + `admin-token-store.ts`
- **#2 SSRF対策**: `shared/url-safety.ts`(登録時・配信直前・テスト送信の3箇所で検証)
- **#3 Access Token JWT化**: `provider.ts`の`formats: { AccessToken: "jwt" }` + `introspection`有効化
- **#4 CORS**: `clientBasedCORS`(Client登録台帳をそのまま許可リストとして使用)
- **#5 テスト**: vitest導入、3ファイルのテスト追加、`TESTING.md`
- **#6 Webhook非同期化**: `webhooks/event-publisher.ts`(fire-and-forget)
- **#7〜#9, #14 K8s/DB**: image tag pinning、NetworkPolicy外部egress、PLAIN削除、readOnlyRootFilesystem対応
- **#10 セキュリティヘッダ/レート制限**: helmet + express-rate-limit
- **#11 Adapter OCP違反**: Strategyパターンへリファクタリング
- **#12 DIP違反**: `password.controller.ts`の見落としも含めてEventPublisherポート経由に統一
- **#13 ページネーション重複**: `shared/pagination.ts`に集約

## 次のステップとして推奨すること

お手元での動作確認手順:

```bash
unzip oidc-dev-server.zip && cd oidc-dev-server
npm install
npx prisma generate
npx prisma migrate dev --name init
npm test              # 追加したユニット/統合テストの実行
npm run dev
```

もし追加で深掘りが必要であれば、以下のような残課題もあります。

- `url-safety.ts`のDNS Rebinding対策は「検証時点」と「実際のfetch時点」の間にわずかなTOCTOUギャップが残っています(コメントで明記済み)。完全に塞ぐには、解決済みIPを直接指定するカスタムDNSレゾルバ/HTTPエージェントの実装が必要です。
- `k8s/deployment.yaml`の`readOnlyRootFilesystem: true`は実機起動検証がまだ済んでいません。

このまま続けて対応してほしい項目があれば教えてください。
