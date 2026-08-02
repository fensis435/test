>`/api/v1/auth/login`(管理API用ログイン)について、これはRailsが管理操作を行う際のサービス間認証として使う想定でしょうか、それとも人間の管理者がツールから使う想定でしょうか。
上記について回答します、「人間の管理者がツールから使う想定」です。
---
最優先要件は「AWS Cognito Hosted UIへの置き換え時に、ReactおよびRailsのコード変更を最小化すること」です。
OIDC Providerの実装はCognitoに依存しない標準OIDC準拠とし、Cognito固有機能への依存はアダプタ層に限定してください。
設計・実装・レビューのすべてで、この要件を最優先にしてください。
---
OIDC Provider設計のみを行ってください。
コードは禁止です。
以下を設計してください。
Authorization Code Flow
PKCE
Discovery
JWKS
Claims
Scopes
Consent
Session
Cookie
Logout
Refresh Token
oidc-providerの設定方針も説明してください。
Cognitoとの差異もまとめてください。

---
---

# OIDC Provider設計(標準OIDC準拠 / Cognito Hosted UI代替)

前回までのDB設計・Management API設計を踏まえ、ここでは**プロトコルコアそのもの**を設計します。最優先要件の観点で最も重要なのは、**このレイヤーが最も「1:1でCognitoの対応物が存在する」領域**であり、だからこそ**Cognito固有仕様を一切混入させず、素のRFC準拠を貫くべき**という点です。前回までのUser CRUD/Webhookとは逆に、ここでの「独自拡張」は最小優先要件への直接的なリスクになります。

---

## 1. Authorization Code Flow

### エンドポイント: `GET /authorize`

**必須クエリパラメータ**

| パラメータ | 説明 | Validation |
|---|---|---|
| response_type | `code`固定 | 他の値は`unsupported_response_type`エラー |
| client_id | Clients.clientIdと一致 | 未登録なら`invalid_client`(かつリダイレクトせずエラー画面表示、後述) |
| redirect_uri | Clients.redirectUrisと完全一致 | 部分一致・ワイルドカードは不可(セキュリティ上の必須制約) |
| scope | スペース区切り。`openid`必須 | `openid`欠如は`invalid_scope` |
| state | CSRF対策トークン | 必須として扱う(oidc-client-ts側もデフォルト付与) |
| code_challenge | PKCE用 | 必須(後述) |
| code_challenge_method | `S256`固定運用 | `plain`は許容しない方針(Cognitoも実質S256前提) |

**任意パラメータ**: `nonce`(ID Token再生攻撃対策。React側は必ず付与すべき)、`prompt`、`max_age`

**フロー**

1. `/authorize` 受信 → client_id/redirect_uri検証 → 未認証ならログイン画面へリダイレクト
2. ログイン成功後、Consent判定(後述)
3. AuthorizationCodeをDB発行(前回設計のAuthorizationCodesテーブル、TTL 60〜600秒、単一使用)
4. `redirect_uri?code=...&state=...` へリダイレクト

**エラーハンドリングの原則**: `redirect_uri`自体が不正な場合はリダイレクトせずブラウザに直接エラー画面を表示する(オープンリダイレクト防止としてRFC/セキュリティBCPが要求する挙動)。それ以外のエラー(`invalid_scope`等)は`redirect_uri?error=...&error_description=...&state=...`でリダイレクト。

### エンドポイント: `POST /token`

**grant_type=authorization_code**

| パラメータ | 必須 | Validation |
|---|---|---|
| grant_type | ✓ | `authorization_code`固定 |
| code | ✓ | 存在・未使用・未失効・TTL内 |
| redirect_uri | ✓ | `/authorize`時と完全一致(RFC必須要件) |
| client_id | ✓ | Public clientの場合、認証方式は次項Client認証を参照 |
| code_verifier | ✓ | PKCE検証(後述) |

**レスポンス**

| フィールド | 型 |
|---|---|
| access_token | JWT |
| token_type | `Bearer` |
| expires_in | integer(秒) |
| refresh_token | string(offline_access scope時のみ) |
| id_token | JWT |
| scope | string |

**エラー**: `invalid_grant`(code不正/期限切れ/使用済み/verifier不一致)、`invalid_client`

---

## 2. PKCE

- `code_challenge_method`は**S256のみサポート**(plainは受理しない)。CognitoもS256を前提としており、ここを揃えることが移行差異ゼロの直接的な担保になる。
- Public Client(React)は**PKCE必須**とし、client_secretなしでの認可コード横取り攻撃を防ぐ。
- 検証ロジック: `/authorize`時に受け取った`code_challenge`をAuthorizationCodesテーブルに保存 → `/token`時の`code_verifier`をSHA256しBase64URLエンコードした値と一致するか検証。
- **Confidential Client(Railsが将来Backend-for-Frontend的に持つ場合)であってもPKCE併用を推奨**(RFC 9700の現行ベストプラクティスに準拠)。

---

## 3. Discovery

### `GET /.well-known/openid-configuration`

Reactのoidc-client-tsは起動時にこのドキュメントを取得し、全エンドポイントURLを動的解決します。**ここがCognito切替時にコード変更ゼロを実現する最大の仕掛け**であり、issuer URLを環境変数で切り替えるだけでReact側のコード変更が不要になる設計の要です。

**必須公開項目**

| フィールド | 内容 |
|---|---|
| issuer | 環境ごとに異なるURL(開発: 自ドメイン、本番: Cognito User Pool URL) |
| authorization_endpoint | `/authorize` |
| token_endpoint | `/token` |
| userinfo_endpoint | `/userinfo` |
| jwks_uri | `/jwks.json` |
| end_session_endpoint | `/logout`(後述の差異注意点あり) |
| response_types_supported | `["code"]` |
| subject_types_supported | `["public"]` |
| id_token_signing_alg_values_supported | `["RS256"]` |
| scopes_supported | `["openid", "email", "profile", "offline_access"]` |
| token_endpoint_auth_methods_supported | `["none", "client_secret_basic"]` |
| code_challenge_methods_supported | `["S256"]` |
| claims_supported | 後述Claims設計と一致させる |

**設計原則**: このドキュメントの公開項目は、**「Reactがoidc-client-ts経由で参照する範囲」に厳密に一致させ、それ以上の項目を増やさない**。過剰な公開情報は将来のCognito Discoveryとの差分を増やすだけ。

---

## 4. JWKS

### `GET /jwks.json`

- RS256の公開鍵セットをJWK形式で公開。`kid`(Key ID)による鍵識別を必須とする。
- **鍵ローテーション方針**: 開発環境では厳密なローテーションは不要(前回のfamilyId reuse detectionと同様、開発用途では簡略化してよい領域)。ただし**`kid`ベースの検証ロジック自体はCognito同様の構造で実装**しておくことで、Rails側のJWT検証コード(JWKS URIから鍵を取得し`kid`でマッチング)は本番Cognito切替時も無改修で動作する。
- 秘密鍵はKubernetes Secretまたは外部KMS的な仕組みで永続化(Pod再起動でのトークン一括失効を防ぐ、前回リスク指摘の対応)。

---

## 5. Claims

Rails側が依存する最小クレーム契約を定義し、これを「アプリケーションが依存してよい唯一の契約」とします。

### ID Token 標準クレーム

| クレーム | 必須 | 説明 |
|---|---|---|
| iss | ✓ | issuer URL |
| sub | ✓ | Users.id(UUID) |
| aud | ✓ | client_id |
| exp / iat | ✓ | 標準 |
| auth_time | – | 認証時刻 |
| nonce | authorize時指定があれば必須 | リプレイ対策 |
| email | scope`email`指定時 | Users.email |
| email_verified | scope`email`指定時 | boolean |
| given_name / family_name | scope`profile`指定時 | – |
| groups | 独自拡張(下記注意) | Users所属Groups.name配列 |

**⚠️重要な設計判断**: `groups`クレームはOIDC標準には存在しない独自拡張です。CognitoはID Tokenに`cognito:groups`という**Cognito固有プレフィックス付き**クレームで出力します。

- 対応方針: 開発OIDC Serverでは**プレフィックスなしの`groups`**という中立的な名前で出力し、Rails側は`groups`という契約名にのみ依存させる。
- Cognito移行時は、**アダプタ層(前回設計のcognito-compat)で`cognito:groups` → `groups`への読み替えを行う**。これにより、Rails側の認可ロジックは`groups`という名前を参照し続けるだけでよく、コード変更が発生しない。
- **この設計判断こそが、Claims設計における最優先要件の核心**です。

### Access Token

- **方針: Access TokenにはUserinfo相当のクレームを含めない**(`sub`, `scope`, `client_id`, `exp`程度の最小構成)。
- 理由: 前回リスク指摘の通り、**Cognitoのデフォルト設定ではAccess Tokenにemail等が含まれない**。開発サーバーだけAccess Tokenにprofile情報を詰め込むと、本番切替時にRailsの「Access Tokenからemailを読む」ロジックが静かに壊れる。**Railsはprofile系情報が必要な場合、必ずID TokenまたはUserinfoエンドポイントを参照する設計に統一**しておくべき。

### `GET /userinfo`

Access Tokenを受け取り、scopeに応じたクレームをJSON返却。ID Tokenと同一のクレームセットを提供し、Rails/Reactどちらから呼ばれても一貫した情報源として機能させる。

---

## 6. Scopes

| Scope | 内容 |
|---|---|
| openid | 必須。sub発行の起点 |
| email | email, email_verified |
| profile | given_name, family_name |
| offline_access | refresh_token発行を許可 |

Cognitoの標準スコープ(`openid`, `email`, `profile`, `aws.cognito.signin.user.admin`等)と極力語彙を合わせつつ、`aws.cognito.signin.user.admin`のようなCognito専用スコープは**開発サーバーでは定義しない**(Reactが依存しないよう設計段階で排除)。

---

## 7. Consent(同意画面)

**方針: 開発環境では原則スキップ**を推奨します。

- 理由: Reactアプリが自社所有の1st-party clientである前提のため、毎回の同意画面はUXコストのみでセキュリティ価値が薄い。
- Cognito Hosted UIも、自社App Client(1st party)に対しては明示的なConsent画面を挟まない構成が一般的であり、**この点はむしろ挙動を揃えやすい**。
- 設計としては`Clients`テーブルに`skipConsent: boolean`(または`consentRequired`)フラグを持たせ、開発用Reactクライアントは`true`(スキップ)に設定。将来サードパーティ連携を追加する場合のみConsent画面を有効化できるよう、**機構自体は残しつつデフォルトOFF**とする。

---

## 8. Session

- OIDC Provider側の内部セッション(前回DB設計のSessionsテーブル)は、**ブラウザCookieセッション**と**発行済みトークン群**を紐付ける役割を持つ。
- `sub`(ログイン中ユーザー)、認証時刻、associatedなRefreshTokensを管理し、`/authorize`再訪問時のSSO判定(再ログイン不要の判定)に利用。
- **Cognito Hosted UIも同様に内部でCookieベースセッションを持つため、この設計の対応関係は良好**。ただしCognito側の具体的なセッションCookie名・属性はブラックボックスであり、開発側はそれを模倣する必要はない(Reactはこの内部Cookieの中身を直接参照しない設計にしておくことが前提)。

---

## 9. Cookie

| Cookie | 属性方針 |
|---|---|
| セッションCookie(IdP内部用) | `HttpOnly`, `Secure`(本番相当環境), `SameSite=Lax`, IdPドメインにスコープ(Reactの動作ドメインとは別) |
| interaction用一時Cookie(ログインフロー中の状態保持) | 短命、`HttpOnly`必須 |

**設計原則**: これらのCookieは**IdP自身が内部的に使うものであり、React/Railsのアプリケーションコードが直接読み書きすることは想定しない**。oidc-client-tsはトークンをブラウザメモリ/sessionStorageで管理する構成が標準であり、IdP内部Cookieへの依存は最初から発生しない設計にする(依存させないことが移行容易性の担保)。

---

## 10. Logout ── 最重要差異ポイント

前回のレビューで既出の通り、**ここが「コード変更ゼロ」を完全には達成できない、唯一の正直な例外ポイント**です。改めて設計として明示します。

### 標準RP-Initiated Logout(OIDC標準)

```
GET /logout?id_token_hint=...&post_logout_redirect_uri=...&state=...
```

oidc-client-tsの`signoutRedirect()`はこの標準形式を前提に動作します。開発OIDC Serverはこの標準形式で実装します。

### Cognitoの実際の仕様(非標準)

Cognitoの`/logout`は`client_id`と`logout_uri`という**独自パラメータ**を要求し、`id_token_hint`ベースの標準RP-Initiated Logoutをサポートしません。

### 対応方針

1. **Reactにログアウト処理の薄いラッパー関数を用意**(前回のレビューで既提案)。呼び出し側コンポーネントは`authService.logout()`のような抽象名のみを呼び、内部実装(標準signoutRedirect呼び出し or Cognito固有パラメータ組み立て)はラッパー内に閉じ込める。
2. この結果、**「Reactの1つのラッパー関数の中身」だけが移行時の変更対象**となり、呼び出し側のコンポーネント・画面コードは無変更。最優先要件の「最小化」を、「完全ゼロ」ではなく「変更範囲をラッパー1箇所に限定する」形で満たす設計判断とします。
3. Rails側はLogoutに関与しない設計(Logoutはブラウザ⇄IdP間のリダイレクトのみで完結させ、Railsがセッション破棄のトリガーになる設計は避ける)。これによりRails側の変更は発生しません。

---

## 11. Refresh Token

- **grant_type=refresh_token**を`/token`でサポート。
- **ローテーション方式を採用**(前回DB設計のfamilyId構造を利用): リフレッシュのたびに新しいRefreshTokenを発行し、古いものは`revokedAt`設定、`replacedByTokenId`で連結。
- **Reuse Detection: 厳密実装は不要**(前回確認済み回答通り)。simplest本の実装として「既にrevoke済みのトークンが再提示されたら、そのリクエストを`invalid_grant`で拒否する」程度に留め、family全体の連鎖失効のような高度な防御は開発環境では省略してよい。
- **有効期限方針**: Access Token短命(例: 15〜60分)、Refresh Token長命(例: 30日)。Cognitoのデフォルト値(Access Token 60分、Refresh Token 30日)に近い値を採用しておくと、本番切替時のUX(再ログイン頻度)の体感差異が小さくなる。

---

## 12. oidc-provider(node-oidc-provider)の設定方針

`oidc-provider`ライブラリを使う場合の設定方針を、機能ごとに整理します。

| 設定項目 | 方針 |
|---|---|
| `features.devInteractions` | **無効化**。デフォルトの開発用ログイン画面はCognito Hosted UIの見た目と乖離するため、独自ログイン画面(`interactions`)を実装する |
| `features.revocation` | 有効化(`/revoke`エンドポイントもRFC 7009準拠で公開しておくと、将来的な柔軟性が高い) |
| `features.rpInitiatedLogout` | 有効化(標準Logoutをそのまま使う。前述の通りCognitoとの差異はReact側ラッパーで吸収) |
| `features.resourceIndicators` | 無効(Cognitoにも対応物がなく、スコープを複雑化させるだけなので不要) |
| `clientAuthMethods` | `['none', 'client_secret_basic']`。Public client(React)は`none`、Confidential(将来のRails BFF等)は`client_secret_basic` |
| `pkce.required` | 全クライアントで必須化(function設定で常にtrueを返す) |
| `ttl.AuthorizationCode` | 60秒程度の短命設定 |
| `ttl.AccessToken` | 3600秒(Cognitoデフォルトに近似) |
| `ttl.RefreshToken` | 2592000秒(30日) |
| `claims` | 前述のClaims設計に厳密一致させ、Cognito固有クレーム名(`cognito:*`)は一切含めない |
| `jwks` | 起動時に外部(K8s Secret等)から読み込み、Pod再起動時も同一鍵を維持 |
| `adapter` | 標準adapterインターフェースに準拠したカスタムPrisma/SQLite adapterを実装(AuthorizationCode, RefreshToken, Session, ClientモデルをDB設計とマッピング) |
| `interactions.url` | 独自ログイン/Consent画面へのリダイレクト先を指定。UIはCognito Hosted UIに寄せたスタイリングを別途フロントで用意可能(これはUI層の話でありOIDCプロトコルの差異ではない) |
| `cookies.keys` | 署名用シークレット。K8s Secretで管理 |
| `extraTokenClaims` / `findAccount` | Groups等の独自クレームをここで注入。前述の通り`groups`のようなプレフィックスなし中立命名を徹底 |

**oidc-provider選定の妥当性**: このライブラリはOAuth2/OIDCの各RFCに忠実な実装であり、Cognito固有仕様(独自Logout等)を持ち込まない限り、標準準拠のコア実装として最優先要件に合致します。**カスタマイズを加える箇所(`extraTokenClaims`, `interactions`)こそが、将来Cognitoとの差異が生まれる箇所であるという自覚を持って設定することが重要**です。

---

## 13. Cognitoとの差異総括表

| 項目 | 開発OIDC Server | Cognito本番 | 移行時の影響範囲 |
|---|---|---|---|
| Authorization Code + PKCE | 標準RFC準拠 | 標準準拠 | **なし**(コード変更不要) |
| Discovery | 標準準拠、issuerのみ環境変数化 | 標準準拠 | **なし**(env切替のみ) |
| JWKS | 標準準拠、kidベース検証 | 標準準拠 | **なし** |
| Claims(email/profile) | 標準クレーム名 | 標準クレーム名 | **なし** |
| Claims(groups) | 中立名`groups`、adapterで吸収 | `cognito:groups` | **アダプタ層のみ**変更 |
| Access Tokenの中身 | 最小構成に統一済み | profile情報を含まない | **なし**(最初から揃えてある) |
| Scopes | 標準+`offline_access` | 同様、Cognito固有scopeは不使用 | **なし** |
| Consent | 1st partyはスキップ | 1st partyは実質スキップ相当 | **なし** |
| Session/Cookie | IdP内部限定、App非依存 | 同様にブラックボックス | **なし** |
| **Logout** | 標準RP-Initiated Logout | **独自パラメータ形式** | **Reactのラッパー関数内のみ**変更(唯一の既知の必須変更点) |
| Refresh Token | ローテーション方式、reuse detection簡易 | 内部実装非公開だが挙動は類似 | **なし**(TTL等の値調整程度) |
| User CRUD/Password/Enable-Disable/Groups管理/Webhook | 独自REST API(前回設計) | AWS Admin API / Lambdaトリガー | **RailsのPort実装(アダプタ)のみ**変更 |
| 管理者ログイン(`/api/v1/auth/login`) | 独自ROPC的API | 対応物なし(IAM/Cognito管理コンソール等) | **管理ツール側のみ**、Reactアプリ本体には影響なし |

---

以上を踏まえると、**「React/Railsのコード変更ゼロ」を達成できるのはOIDCプロトコルコア部分のみ**であり、**Logout(Reactラッパー1箇所)とIdentity/Webhook系(RailsのPort実装)の2箇所が、設計上受け入れるべき現実的な変更範囲**として明確に切り分けられています。この切り分け自体を設計文書(ADR)として残すことを推奨します。

一点ご確認したいのですが、Groupsクレームの命名を`groups`という中立名にする方針について、Rails側の認可ロジック(OPA/Casbin等、以前のメモリにあったAuthorization検討)は既にこの命名を前提に設計が進んでいますでしょうか。もしまだであれば、認可エンジン側のクレーム参照名をこのタイミングで確定させておくと、後工程での手戻りを防げます。
