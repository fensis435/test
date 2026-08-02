最優先要件は「AWS Cognito Hosted UIへの置き換え時に、ReactおよびRailsのコード変更を最小化すること」です。
OIDC Providerの実装はCognitoに依存しない標準OIDC準拠とし、Cognito固有機能への依存はアダプタ層に限定してください。
設計・実装・レビューのすべてで、この要件を最優先にしてください。
---
あなたはOAuth2/OIDCおよびNode.jsのPrincipal Architectです。
コードは一切書かないでください。
これから開発用OIDC Serverを作ります。
目的はAWS Cognito Hosted UIの代替です。
React(Vite)+oidc-client-ts
Rails8(API)
から利用されます。
本番ではCognitoへ切替えます。
要求は
・Authorization Code + PKCE
・Discovery
・JWKS
・User CRUD
・Webhook通知
・SQLite
・Kubernetes
です。
以下についてレビューしてください。
1. システム構成
2. 責務分割
3. ディレクトリ構成
4. DDD観点
5. SOLID観点
6. 将来Cognitoへ置き換える際の差異
7. リスク
8. 改善案
コードは禁止です。

---
---

# レビュー: 開発用OIDC Server(Cognito Hosted UI代替)アーキテクチャ

最優先要件を軸に、Principal Architectとして8観点でレビューします。結論を先に言うと、**最大のリスクは「OIDC標準の実装そのもの」よりも「User CRUDとWebhookという、Cognitoに存在しない機能をApp側が直接叩いてしまうこと」**です。ここを設計で塞げるかが成否を分けます。

---

## 1. システム構成

構成要素を機能ごとに分離して捉えるべきです。

- **OIDC Protocol Core**: `/​.well-known/openid-configuration`、`/jwks.json`、`/authorize`、`/token`、`/userinfo`、`/logout(or /revoke)` — RFC準拠のみ。Cognitoの知識を一切持たない。
- **Identity Management (User CRUD)**: 管理者向けAPI。OIDC標準には存在しない独自機能。**本番のCognitoにはこの形のAPIは存在しない**(AdminCreateUser等のAWS SDK経由になる)。
- **Webhook Dispatcher**: ユーザー作成/更新等のイベント通知。これもOIDC標準外。**CognitoにはWebhookという概念自体が存在せず、Lambdaトリガー(PreSignUp/PostConfirmation/PreTokenGeneration等)が相当する**。同期呼び出しモデルであり、非同期HTTP Webhookとは根本的に異なる。
- **永続化**: SQLite(単一障害点になりうる。後述)
- **Frontend**: React(oidc-client-ts)は**Discoveryドキュメントで公開された標準エンドポイントのみ**を叩く。User CRUD/Webhook設定など非標準APIには絶対に直接触れさせない。
- **Rails API**: JWT検証はJWKS URIベース(discoveryから取得)。issuer/audienceは環境変数駆動とし、コードにCognitoのURLをハードコードしない。

React → OIDC Coreのラインと、Rails → Identity/Webhookのラインを明確に分離するのが構成上のキモです。

---

## 2. 責務分割

| コンポーネント | 責務 | 本番Cognitoでの対応 |
|---|---|---|
| OIDC Core | 認証プロトコルのみ | Cognito Hosted UI/Token Endpointがそのまま代替 |
| Identity CRUD | 開発用ユーザー管理 | AWS Admin API / IaC / 運用ツール(アプリコードではない) |
| Webhook | イベント通知 | Lambdaトリガー + (必要なら)EventBridge |
| Cognito互換Adapter | クレーム整形・エンドポイント差異吸収 | 本番では実装差し替え対象そのもの |

**責務分割の判断基準は「Cognitoに1:1で存在する機能か否か」であるべきです。** 存在する機能(OIDC Core)は標準準拠を徹底し、存在しない機能(CRUD/Webhook)はApp側から見て「抽象化されたポート」越しにしかアクセスできないようにする。ここが最優先要件に直結する設計判断です。

---

## 3. ディレクトリ構成

責務分割をそのままディレクトリに落とし込み、「Cognito固有知識の置き場所」を1箇所に限定します。

```
/src
  /oidc-core/           # authorize, token, jwks, discovery, PKCE検証(RFC準拠、Cognito非依存)
  /identity/            # User CRUD ドメイン(開発専用bounded context)
  /webhooks/            # イベント配信(開発専用bounded context)
  /adapters/
    /cognito-compat/    # クレーム名・ログアウトパラメータなどCognito固有仕様を吸収する層
                         # ← Cognito固有知識はここにしか存在してはならない
  /infra/
    /persistence/        # SQLiteリポジトリ
    /http/                # ルーティング層
  /config/                # issuer, JWKS鍵, audience(env駆動)
/k8s/
  deployment.yaml / service.yaml / ingress.yaml / pvc.yaml / configmap.yaml / secret.yaml
```

ポイントは `adapters/cognito-compat` の存在です。ここは「今は使わないが、将来Cognitoのクレーム形式(`cognito:username`, `cognito:groups`, `token_use`等)に寄せるための変換ロジックを置く場所」として、開発初期から確保しておくべきです。

---

## 4. DDD観点

Bounded Contextとして OIDC Core / Identity / Webhook を分離した上で、**それぞれの「本番との写像関係」が全く違う**ことがDDD上の核心的リスクです。

- **OIDC Core = Shared Kernel(準共有カーネル)**: 開発環境と本番Cognitoで契約(discovery, JWKS, token構造)がほぼ一致すべき領域。
- **Identity / Webhook = 開発専用Context、本番では別モデルに置換**: ここにApp(React/Rails)が直接依存すると、置換時に確実にコード変更が発生する。

対策は**腐敗防止層(Anti-Corruption Layer)をApp側とIdP側の境界に置くこと**です。RailsはOIDC Core検証以外は「IdentityManagementPort」「UserLifecycleEventPort」のような自前定義のインターフェースにのみ依存し、その実装が開発用OIDC ServerかCognito SDKかは知らない、という構造にする。これはヘキサゴナルアーキテクチャそのものであり、最優先要件を満たす唯一の現実的な設計です。

ユビキタス言語としても、「webhook」「CRUD API」といった実装寄りの語をApp側ドメインコードに漏らさず、「subject」「claims」「user lifecycle event」など標準OIDC/ドメイン語彙に統一すべきです。

---

## 5. SOLID観点

- **SRP**: OIDC Core / Identity / Webhookのクラス・モジュール分離は済んでいる前提で良い。
- **OCP**: クレーム整形をStrategyパターン化し、IdP切替=Strategy実装差し替えのみで完結させる。Core本体の修正が発生した時点で設計失敗。
- **LSP**: 「IdentityProviderPort」のようなインターフェースを定義する場合、開発用AdapterとCognito Adapterは完全代替可能でなければならない。呼び出し側(Rails)が「これは開発用だから」と分岐するコードを書いた瞬間にLSP違反であり、最優先要件の破綻でもある。
- **ISP**: Rails/Reactが依存するインターフェースは最小限に。TokenValidation(検証のみ)とUserManagement(管理者専用)を分離し、App本体はTokenValidationにしか依存しないようにする。依存面積が小さいほど置換コストは下がる。
- **DIP**: エンドポイントのハードコード禁止。Reactはoidc-client-tsのDiscovery機能で実行時解決、RailsはJWKSキャッシュをissuer設定から動的取得。抽象(標準OIDC契約)に依存し、具象(開発サーバーの実装詳細)に依存しない。

---

## 6. 将来Cognitoへ置き換える際の差異

ここが最優先要件に対する最大の技術的チェックリストです。

1. **クレーム名の差異**: Cognitoは `cognito:username`, `cognito:groups`, `token_use`, `custom:*` を使う。App(特にRails認可ロジック)が参照するクレーム名は、開発サーバー側でCognito互換に整形するか、逆にAppが依存する最小クレーム契約を自前定義し、両IdPともそこにマッピングするかを今決める必要がある。
2. **ID Token vs Access Token**: **Cognitoのデフォルト設定ではAccess Tokenにemailやcustom属性が含まれません**(ID Tokenのみ)。これは非常によく踏む地雷で、RailsがAccess Tokenだけでprofile情報を取ろうとする設計だと本番で壊れます。今のうちにどちらのトークンで何を検証するか契約化すべき。
3. **Logout(RP-Initiated Logout)の非標準性**: Cognitoの `/logout` は標準OIDC RP-Initiated Logout(`id_token_hint` + `post_logout_redirect_uri`)ではなく、独自パラメータ(`client_id`, `logout_uri`)を要求します。oidc-client-tsの `signoutRedirect()` は標準準拠を前提にしているため、**これはこのプロジェクト固有の問題ではなくCognito自体の仕様非準拠に起因する、避けられない差異**です。最初からReact側にログアウト処理の薄いラッパーを用意し、実装差し替えで吸収できるようにしておくべき。
4. **PKCE/Public Client設定**: Cognitoの App Client (client secretなし)と同一の設定モデル(scope: openid email profile等)に開発サーバーを合わせる。
5. **User CRUD**: Cognito本番にはApp向けの汎用CRUD APIは存在しない。もしReact/Railsがこの開発用CRUD APIに直接依存していたら、**その依存は必ず書き換えが発生します**。IdentityManagementPort越しにのみアクセスする設計が必須。
6. **Webhook**: Cognitoの代替はLambdaトリガー(同期呼び出し)。現在Webhook受信として作るRails側のエンドポイントが「HTTPでイベントを受け取る」という抽象のままであれば、送信側がLambda経由のHTTPS呼び出しに変わるだけで済む可能性が高い。ただし同期/非同期・タイムアウト制約の違いは設計に影響するため要検討。
7. **JWKS鍵ローテーション**: Cognitoは自動管理。開発サーバーは自前で鍵ライフサイクルを設計する必要があり、ここでの運用差異は本番切替時のコード差異にはならないが、テストの信頼性には影響する。

---

## 7. リスク

- **SQLite + Kubernetes マルチレプリカ**: ファイルロック競合、複数Pod間の一貫性欠如。PKCEの認可コード保存やセッション状態がレプリカ間で不整合を起こす。**単一レプリカ(StatefulSet相当)+PVCを明示的な制約として設計に組み込む**必要がある。
- **署名鍵の永続化不備**: JWK鍵をPod再起動のたびに再生成すると、発行済みトークンが即座に無効化される。PVCまたは外部Secret管理必須。
- **Access/ID Tokenのクレーム差異による静かな失敗**: 開発環境では動くが本番Cognitoでのみ認可が壊れる、という典型的な地雷(前述6-2)。
- **Logout仕様差異**: 「コード変更ゼロ」を掲げても、Cognito自体の非標準性により完全ゼロは非現実的。例外として明示的に許容すべき。
- **User CRUD / Webhookへの安易な直接依存**: 最優先要件そのものを破壊する最大のリスク。設計レビューだけでなく、コードレビュー時にも「Reactから非標準APIを直接叩いていないか」を継続監視する運用ルールが必要。
- **セキュリティ機能の非対称性**: Cognito Hosted UIが持つレート制限、不正検知、MFA、アカウント回復等を開発サーバーは持たない。QA/E2Eがこれを「同等」とみなすと本番のセキュリティギャップを見逃す。
- **Discoveryドキュメントの乖離**: 開発サーバーが対応アルゴリズムやscopeをCognitoと異なる形で広告すると、統合テストが本番の制約を検出できない。

---

## 8. 改善案

1. **Port & Adapterパターンの明文化**: `TokenVerifierPort` / `IdentityManagementPort` / `UserLifecycleEventPort` をRails側に定義し、開発OIDCサーバー用Adapterと将来のCognito Adapterの両方がこれを実装する。これが最優先要件を満たす中心設計。
2. **クレーム契約(Claims Contract)の明示・バージョン管理**: App(特にRails)が依存する最小クレームセット(`sub`, `email`, `roles`等)を定義し、開発サーバー・Cognito双方がこの契約に整形して出力する。契約テストを両IdPに対して実行する。
3. **Reactの依存範囲を標準OIDCフローのみに限定**: discovery, authorize+PKCE, token, userinfo, silent renewのみ。User CRUD/Webhook設定は必ずRails経由にし、React自体はIdP切替の影響を受けない設計にする。
4. **Logoutラッパーの前倒し実装**: `signoutRedirect()`を直接呼ばず、自前の薄いラッパー関数を最初から用意。Cognitoの非標準ログアウトへの対応をラッパー内部の実装差し替えのみに限定する。
5. **Webhook受信側をprovider非依存に設計**: Rails側のイベント受信エンドポイントは「HTTPでライフサイクルイベントを受け取る」という抽象のままにし、送信側(開発サーバー vs Lambda経由)の差異のみで吸収できるようにする。
6. **早期のCognitoサンドボックス併用**: 開発の比較的早い段階で、実際のAWS Cognito User Poolを使った統合テストの対象を一部作り、クレーム構造・discoveryドキュメント・ログアウト挙動の差分を継続的に検出する。
7. **ADRとして差異を記録**: 本レビューの第6項の内容を正式なADR化し、各項目に対する意思決定と担当者を明記する。
8. **Kubernetesトポロジの明示的制約化**: SQLite単一レプリカ構成は「開発専用の非HA構成」であることをマニフェスト・ドキュメント双方に明記し、本番のCognito(フルマネージドHA)とのスケーラビリティ前提の混同を防ぐ。

---

総括すると、OIDCプロトコル自体の標準準拠は比較的リスクが低い一方、**User CRUDとWebhookという「Cognitoに存在しない機能」への直接依存が、最優先要件にとって最大の脅威**です。設計フェーズで Port & Adapter を徹底し、React/Railsが「今使っているのが開発用OIDCサーバーである」ことを意識せずに済む抽象化を最初から作り込むことを強く推奨します。

