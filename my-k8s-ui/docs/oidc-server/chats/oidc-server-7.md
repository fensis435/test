最優先要件は「AWS Cognito Hosted UIへの置き換え時に、ReactおよびRailsのコード変更を最小化すること」です。
OIDC Providerの実装はCognitoに依存しない標準OIDC準拠とし、Cognito固有機能への依存はアダプタ層に限定してください。
設計・実装・レビューのすべてで、この要件を最優先にしてください。
---
Principal Engineerとしてレビューしてください。
コードは変更しません。
レビューだけ行ってください。
以下を指摘してください。
SOLID
DDD
Security
OIDC準拠
Cognito互換性
保守性
性能
テスト性
Kubernetes
改善点
100点満点で採点してください。
修正すべき箇所だけ一覧化してください。

---
---

# Principal Engineerレビュー: oidc-dev-server実装

コードは変更せず、指摘のみ行います。前提として本レビューは実際に生成済みのソースコード(全32 TSファイル + K8sマニフェスト)を精査した結果です。

---

## 総合スコア: **63 / 100**

| 観点 | スコア | 一言 |
|---|---|---|
| SOLID | 70 | 概ね良好だが、Adapterのswitch文と Webhook直接依存がOCP/DIPに反する |
| DDD | 65 | Bounded Context分離は folder レベルで機能しているが、実態はTransaction Script |
| Security | 55 | **管理者トークン失効が機能していない**。SSRF・レート制限・CORSが未実装 |
| OIDC準拠 | 60 | **Access TokenがデフォルトOpaque**でRails側JWKS検証設計と矛盾 |
| Cognito互換性 | 70 | クレーム設計は健全だが、AT形式不一致が本番パリティを崩す |
| 保守性 | 68 | ページネーション/レスポンス変換の重複、構造化ログ欠如 |
| 性能 | 62 | Webhook配信がリクエストパス内で同期実行されている |
| テスト性 | 40 | **テストコードが一切存在しない**。DI欠如でモック困難 |
| Kubernetes | 72 | 土台は良いが `:latest` タグ、NetworkPolicyの外部疎通考慮漏れ |

---

## 1. SOLID (70点)

- **OCP違反**: `PrismaOidcAdapter`が`this.model`による巨大switch文でClient/AuthorizationCode/RefreshToken/genericを分岐している。新しいoidc-providerモデル対応時にこのクラス自体を修正する必要があり、当初設計で明言した「Strategyパターン化」方針(SOLIDレビュー時の確定事項)と矛盾する。
- **DIP違反**: `users.service.ts` / `groups.service.ts`が`webhooks/dispatcher.ts`の`dispatchWebhookEvent`を直接importして呼び出している。抽象(`EventPublisher`ポート等)を介さず具象実装に直接依存しており、最優先要件で掲げた「Port & Adapter」思想が識別層(Identity)とWebhook層の間には適用されていない。
- **SRP違反**: `PrismaOidcAdapter`は1クラスで4種類の永続化戦略(Client/AuthorizationCode/RefreshToken/Generic)を担っており責務過多。
- **DRY/SRP**: 各コントローラで`{ type: "ADMIN_USER", id: req.adminUserId ?? null }`というactor構築コードが users/groups/clients に重複。

## 2. DDD (65点)

- ドメイン層が存在せず、サービス層はPrisma呼び出しの並びに終始する**Transaction Script**パターン。Bounded Context分離はディレクトリ構造上は機能しているが、Entity/Value Objectとしての不変条件(例: Emailの正規化ルール)がドメインオブジェクトとして表現されていない。
- `users.service.deleteUser` / `disableUser`が同一トランザクション内でUser・RefreshToken・Sessionという複数集約に直接またがって更新しており、集約境界が事実上ない。
- ドメインイベント(`user.created`等)の発行が、書き込み処理と**同一リクエストの同期パス**で行われており、イベント駆動としての疎結合性がない(3番の性能項目と関連)。

## 3. Security (55点) ── 最重要

- **【重大】管理者トークンの失効が機能していない**: `admin-auth.controller.ts`の`logout()`は`revokedJti`にjtiを追加するが、`admin-auth.middleware.ts`の`requireAdminAuth`はこの`isRevoked()`を一度も参照していない。ログアウト後もトークンの有効期限まで**Management API全体に対して有効なまま**になる。
- **【重大】SSRFリスク**: Webhook登録(`createWebhookBodySchema`)は`targetUrl`を`z.string().url()`でのみ検証しており、プライベートIPレンジ・`localhost`・クラウドメタデータエンドポイント(`169.254.169.254`)への登録を防いでいない。`dispatcher.ts`および`testWebhookHandler`がこのURLに対して無制限に`fetch`する。
- レート制限が全エンドポイントに存在しない(admin login含む)。`express-rate-limit`等の導入なし。
- `express()`にセキュリティヘッダ用ミドルウェア(`helmet`)が未導入。interaction画面はHTMLをinline生成しており、CSPヘッダがない状態でXSS対策をescapeHtmlのみに依存している。
- Prisma `CodeChallengeMethod` enumに`PLAIN`が残存。`provider.ts`側で`pkce.methods: ["S256"]`により実質無効化されているとはいえ、データ層でも許容されている点は多層防御の観点で改善余地。
- CORS設定が明示的にどこにも存在しない。React(Vite: 別オリジン)から`/token`・`/userinfo`をfetchする構成のため、oidc-providerの`clientBasedCORS`設定漏れの可能性がある(4番で詳述)。

## 4. OIDC準拠 (60点)

- **【重大】Access Tokenの形式が設計と矛盾**: `provider.ts`に`formats: { AccessToken: "jwt" }`相当の設定がない。oidc-providerのデフォルトでは**Access Tokenはopaque**として発行される。一方、以前確定した設計・メモリには「RailsはJWKS URIベースでJWT検証する」という前提があり、opaqueのままではRailsが`/userinfo`または`/introspect`なしにAccess Tokenを検証できない。
- 上記の帰結として**`features.introspection`が有効化されていない**。Access Tokenがopaqueである以上、Resource Server(Rails)側の検証手段が事実上存在しない。
- **`clientBasedCORS`が未設定**。ReactのオリジンとIssuerのオリジンが異なる場合(Vite: `localhost:5173` vs Issuer: `localhost:3000`)、`/token`エンドポイントへのブラウザからのfetchがCORSでブロックされる可能性が高い。oidc-provider v8ではこの関数を明示的に設定しない限り既定で許可されない。
- `features.rpInitiatedLogout`はデフォルトの確認画面(logoutSource)のまま。1st-partyクライアントに対するConsentスキップ方針と整合させるなら、Logoutの確認画面もスキップまたはカスタマイズすべきという設計上の一貫性の欠如。

## 5. Cognito互換性 (70点)

- クレーム命名(`groups`中立化)は健全に実装されている。
- 前述のAccess Token形式の不一致(opaque vs JWT)は、**本番Cognito(JWT形式のAT)との重大な挙動差**であり、Cognito互換性の観点では最も深刻な項目。dev環境で「AT検証」を伴うテストが一切機能しないため、本番切替時に初めてバグが顕在化するリスクが高い。
- `src/adapters/cognito-compat/claims-mapper.ts`はコードベース内のどこからも呼び出されておらず(意図通り「リファレンス実装」)、テストも存在しない。ドキュメントとしての価値はあるが、Rails側実装との同期を保証する仕組み(契約テスト等)がなく、将来的な陳腐化リスクがある。

## 6. 保守性 (68点)

- カーソルページネーションロジック(`take`/`cursor`/`hasMore`/`nextCursor`計算)がusers/groups/clients/webhooksの4サービスにほぼ同一のコードとして重複している。共通ユーティリティ化すべき。
- `toXxxResponse()`関数群がJSON文字列カラム(`redirectUris`, `allowedScopes`等)を無条件に`JSON.parse`しており、DB破損時に生の例外が500として露出する(型安全性の担保なし)。
- `console.log`/`console.error`による素朴なロギングのみ。Kubernetes環境での運用を考えると、構造化ログ(JSON形式)・相関ID(request id)の欠如は監視性を大きく損なう。
- 以前設計したOpenAPIドキュメント(Request/Response/Error形式)が、zodスキーマとしてはコード化されているが、実際のOpenAPI仕様書(`openapi.yaml`等)としては出力されていない。設計文書と実装の乖離リスク。

## 7. 性能 (62点)

- **`dispatchWebhookEvent`がAPIリクエストのクリティカルパス内で同期的に配信を試みている**。`users.service.createUser`等はWebhook配信先の応答を待ってからHTTPレスポンスを返す構造になっており、Webhook受信側の遅延・障害がUser CRUD APIのレイテンシに直結する。
- 複数Webhook Subscriptionが登録されている場合、`for...of`ループで**逐次await**しており並列化されていない。
- `adapter.ts`の`resolveClientRowId`が、AuthorizationCode/RefreshToken発行のたびに`Client`テーブルへ追加のDBラウンドトリップを発生させている(N+1傾向。Clientはほぼ不変なためキャッシュ可能)。

## 8. テスト性 (40点) ── 要改善

- **テストコードが一切存在しない**(unit/integration/e2e問わず、テストフレームワークの導入もなし)。
- `prisma`シングルトンが各サービス・アダプタから直接importされており、DIコンテナやリポジトリ抽象が存在しないため、モック差し替えが困難(実DBまたはモジュールモンキーパッチが必要)。
- `dispatcher.ts`はグローバルな`fetch`を直接呼び出しており、HTTPクライアントの注入点がない。ネットワークモック(`nock`/`msw`)なしにユニットテストが書けない。
- 管理者トークンの`revokedJti`がモジュールレベルの可変Setであり、テスト間での状態リークが発生しうるグローバル状態。

## 9. Kubernetes (72点)

- `deployment.yaml`の`image`が`:latest`タグ。`imagePullPolicy: IfNotPresent`との組み合わせは再現性のないデプロイを招く(ロールバック時に異なるイメージが取得される可能性)。immutableタグまたはdigest指定が必須。
- `readOnlyRootFilesystem: true`を設定しているが、Prisma Query Engineが実行時に一時ソケット/ログファイルを書き込む可能性があり、実機検証なしにこの設定が機能するかは未確認(潜在的な起動失敗リスク)。
- `networkpolicy.yaml`のegressルールは`namespaceSelector: {}`(クラスタ内Podのみ)に限定されており、**クラスタ外部のWebhook宛先への疎通が実質ブロックされる**。Webhook機能は元設計上「内部/外部いずれのURLも登録可能」としていたため、外部向けegress(ipBlockでの許可リスト、またはEgress Gateway経由)が考慮されていない。
- `imagePullSecrets`が未定義(プライベートレジストリ利用前提が明記されているにも関わらず)。
- IdPという重要インフラコンポーネントに対して`PriorityClass`が設定されておらず、ノードリソース逼迫時に他のワークロードと同等に扱われる。

---

## 修正すべき箇所 一覧(優先度順)

1. **`admin-auth.middleware.ts`**: `requireAdminAuth`が`isRevoked(jti)`を検証していない。ログアウト済みトークンが失効しない。
2. **`webhooks.controller.ts` / `dispatcher.ts`**: Webhook `targetUrl`登録時にSSRF対策(プライベートIP/localhost/メタデータエンドポイントの拒否)が未実装。
3. **`provider.ts`**: Access Tokenが未設定によりopaqueのまま発行されている。JWT形式への変更、または`features.introspection`の有効化のいずれかが必要。
4. **`provider.ts`**: `clientBasedCORS`が未設定。React(別オリジン)からの`/token`・`/userinfo`呼び出しがCORSでブロックされる可能性。
5. **プロジェクト全体**: テストコードが皆無。最低限、`users.service`/`groups.service`/`adapter.ts`のユニットテストとPrismaのDI化(モック可能化)が必要。
6. **`webhooks/dispatcher.ts`, `users.service.ts`, `groups.service.ts`**: Webhook配信がAPIリクエストの同期パス内で実行されている。非同期化(キュー/outboxパターン)またはfire-and-forgetへの変更が必要。
7. **`k8s/deployment.yaml`**: `image`タグが`:latest`。immutableタグ/digest指定への変更が必要。
8. **`k8s/networkpolicy.yaml`**: egressルールがクラスタ外部への疎通を許可しておらず、外部Webhook宛先が機能しない。ipBlockベースの許可リスト追加が必要。
9. **`prisma/schema.prisma`**: `CodeChallengeMethod`に`PLAIN`が残存。データ層での多層防御としてenumから削除を検討。
10. **`src/infra/http/app.ts`**: `helmet`等のセキュリティヘッダミドルウェア、レート制限ミドルウェアが未導入。
11. **`oidc-core/adapter.ts`**: モデル種別ごとのswitch文をStrategy/Mapベースの構造にリファクタリングし、OCP違反を解消すべき。
12. **`identity/users.service.ts`, `identity/groups.service.ts`**: `dispatchWebhookEvent`への直接依存をポート(インターフェース)経由に変更し、DIP違反を解消すべき。
13. **各`*.service.ts`のページネーション処理**: 共通ユーティリティへの抽出が必要(4箇所で重複)。
14. **`k8s/deployment.yaml`**: `readOnlyRootFilesystem: true`がPrisma Query Engineの実際の書き込み挙動と両立するか、実機での起動検証が未実施。
