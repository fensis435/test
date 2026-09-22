# テナントルーティング仕様書
## クエリパラメータ + X-Tenant-Id 内部プロトコル方式

- **バージョン**: v0.1(検討用ドラフト)
- **対象**: ポータル(React+MUI SPA) → テナントWebアプリ(Rails8 / Flask / Django / Next.js)接続基盤
- **ステータス**: 検討中(未実装)

---

## 1. 目的・背景

### 1.1 現行方式の課題

現行はワイルドカードサブドメイン(`web-0001-web2.example.com`)のホスト名からnginx ingressがnamespaceを、envoyがサービス名を、それぞれ正規表現で抽出してルーティングしている。AWS移行に伴い、相乗り先ドメインがワイルドカード非対応のため、この方式をそのまま踏襲できない。

### 1.2 本方式の狙い

- ホスト名(Host)ではなく、**接続開始時にクエリパラメータとして渡されるticket**を起点にテナントを解決する
- nginx ingressを唯一の信頼境界とし、そこから先(envoy・Web1/2/3)は**正規化されたヘッダー(`X-Tenant-Id` / `X-Service-Id`)のみを信頼**する内部プロトコルに統一する
- ポータルの「1セッションで複数テナントへ同時接続する」要件(`X-Tab-Id`)と統合する
- 静的アセット配信をテナント解決の対象外に分離し、不要なコールドスタート(scale-to-zeroからの復帰)を避ける

### 1.3 非対象

- CloudFrontなど追加のエッジ層導入(利用可否未確定のため本仕様では前提としない)
- 認可ポリシー(OPA/Cedar等)の詳細設計(別紙とする。本仕様は認可判断の「入力」となるクレームの正規化までを扱う)

---

## 2. 用語定義

| 用語 | 定義 |
|---|---|
| tenant_ns | テナントを表すnamespace名(例: `web-0001`) |
| service_id | namespace内のサービス識別子(例: `web1`, `web2`, `web3`) |
| tab_id | ブラウザの1タブ(ブラウジングコンテキスト)を識別する一意な値 |
| ticket | ポータルが接続開始時に発行する、1回限り・短期TTLの不透明な(opaque)ランダムトークン。tenant_ns・service_id・tab_id・user_idの組を内部的に紐付ける |
| 信頼境界 | クライアント由来の入力を検証し、以降のコンポーネントが無条件に信頼してよい値へと正規化する地点。本方式ではnginx ingressがこれにあたる |

---

## 3. 全体アーキテクチャ

```
[Portal SPA]
     │ (1) 接続API呼び出し(Cookie認証)
     ▼
[Portal Backend] ──(2) ticket発行・Redis保存──▶ [Redis/DynamoDB]
     │ (3) connect URL を返却
     ▼
window.open("https://app.a-corp.com/connect?ticket=xxxx")
     │
     ▼
[nginx ingress] ──(4) auth_request──▶ [Ticket Resolver]──▶[Redis参照]
     │ (5) X-Tenant-Id / X-Service-Id / X-Tab-Id を確定しヘッダー付与
     ▼
[Envoy] (6) X-Service-Id のみでルーティング判断(Hostは見ない)
     │
     ▼
[Web1 / Web2 / Web3] (7) JWTクレームとX-Tenant-Idを突合検証
```

信頼できるのは常に「nginx ingressより内側」であり、それより外側(クライアント・URL・クエリパラメータ)は一切信頼しない、という原則を全レイヤーで一貫させる。

---

## 4. シーケンス

```
User          Portal(SPA)      Portal API        Redis          nginx ingress    Ticket Resolver   Envoy         Web1/2/3
 │ ボタン押下     │                 │                │                │                │              │              │
 ├──────────────▶│                 │                │                │                │              │              │
 │               │ POST /connect   │                │                │                │              │              │
 │               │ (tenant=web-0001, Cookie=session) │                │                │              │              │
 │               ├────────────────▶│                │                │                │              │              │
 │               │                 │ ticket発行     │                │                │              │              │
 │               │                 ├───────────────▶│                │                │              │              │
 │               │                 │ (tenant_ns, service_id, user_id, TTL=60s)          │              │              │
 │               │                 │◀ 保存完了 ─────┤                │                │              │              │
 │               │ connectUrl 応答  │                │                │                │              │              │
 │               │◀────────────────┤                │                │                │              │              │
 │ window.open() │                 │                │                │                │              │              │
 │◀──────────────┤                 │                │                │                │              │              │
 │ 新規ウィンドウでGET /connect?ticket=xxxx&tab=yyyy                  │                │              │              │
 ├─────────────────────────────────────────────────────────────────▶│                │              │              │
 │                                 │                │                │ auth_request   │              │              │
 │                                 │                │                ├───────────────▶│              │              │
 │                                 │                │                │                │ ticket参照   │              │
 │                                 │                │                │                ├─────────────▶│(Redis)      │
 │                                 │                │                │                │◀─ tenant_ns等─┤              │
 │                                 │                │                │◀─ X-Tenant-Ns等─┤              │              │
 │                                 │                │                │ proxy_pass (X-Tenant-Id等付与) │              │
 │                                 │                │                ├───────────────────────────────▶│              │
 │                                 │                │                │                │ header_matchでcluster選択    │
 │                                 │                │                │                │              ├─────────────▶│
 │                                 │                │                │                │              │ JWT突合検証   │
 │◀──────────────────────────────────────────────── HTML(以降 sessionStorage に tab_id/ticket残片を保存)───────────┤
```

---

## 5. Ticket発行API仕様(Portal Backend)

### 5.1 エンドポイント

```
POST /api/connections
Authorization: Cookie(ポータルセッション)
Content-Type: application/json

{
  "tenant_id": "web-0001",
  "service_id": "web2"
}
```

### 5.2 レスポンス

```json
{
  "connect_url": "https://app.a-corp.com/connect?ticket=8f14e45f-ceea-467e-9e97-...&tab=b3f8...",
  "expires_in": 60
}
```

### 5.3 サーバー側処理(Python/Flask例)

```python
import secrets
import time
from flask import Flask, request, jsonify, session

app = Flask(__name__)
TICKET_TTL_SECONDS = 60

@app.post("/api/connections")
def create_connection():
    user_id = session.get("user_id")
    if not user_id:
        return jsonify(error="unauthorized"), 401

    body = request.get_json()
    tenant_id = body.get("tenant_id")
    service_id = body.get("service_id")

    # ユーザーがこのテナントへアクセスする権限を持つか確認
    if not user_has_tenant_access(user_id, tenant_id):
        return jsonify(error="forbidden"), 403

    ticket = secrets.token_urlsafe(32)
    tab_id = request.args.get("tab") or secrets.token_urlsafe(16)

    redis_client.setex(
        f"ticket:{ticket}",
        TICKET_TTL_SECONDS,
        json.dumps({
            "user_id": user_id,
            "tenant_id": tenant_id,
            "service_id": service_id,
            "tab_id": tab_id,
            "issued_at": time.time(),
        }),
    )

    # テナントpodがscale-to-zeroなら、ここでwake-upをトリガー(非同期)
    trigger_tenant_wakeup(tenant_id)

    connect_url = (
        f"https://app.a-corp.com/connect"
        f"?ticket={ticket}&tab={tab_id}"
    )
    return jsonify(connect_url=connect_url, expires_in=TICKET_TTL_SECONDS)
```

**設計上のポイント**

- `ticket`はランダムかつ推測不可能な値(最低128bit相当のエントロピー)とする
- TTLは短く(60秒程度)、初回アクセス完了後は即座に無効化(one-time use)する。再利用が必要な場合(タブのリロード等)は後述5.4を参照
- 発行時点でテナントアクセス権限を検証する(認可判断はここで既に1回行われる)

### 5.4 Ticketの再利用(リロード対応)

Ticketは初回接続専用の使い捨てとし、リロード時の再検証には**別途セッションCookie(nginx ingressの信頼境界で発行するもの)**を用いる。詳細は7.3節を参照。

---

## 6. URLスキーム定義

### 6.1 接続URL(初回ナビゲーション)

```
https://app.a-corp.com/connect?ticket=<opaque>&tab=<opaque>
```

| パラメータ | 必須 | 説明 |
|---|---|---|
| `ticket` | ○ | 5章で発行されたワンタイムticket |
| `tab` | ○ | ブラウザタブを識別する値。Portal側でクライアント生成(`crypto.randomUUID()`)し、ticket発行APIにも渡すことでRedis上の紐付けに含める |

### 6.2 テナント固有パス(ドキュメント・API)

Ticket解決後、内部的にnginx ingressが`$tenant_ns` / `$service_id`を確定させ、以降は9章のクライアント実装がヘッダーで運ぶ。**URL自体には`tenant_ns`を露出させない**(ticketは使い捨てのため、接続確立後のURLはCookie/ヘッダーに依拠する)。

### 6.3 静的アセットパス(テナント非依存)

```
/_next/static/*
/assets/*
/static/*
```

これらは`ticket`の解決を経由しない共有配信経路とする(11章)。

---

## 7. nginx ingress仕様

### 7.1 auth_requestによるticket解決

```nginx
location = /_ticket_resolve {
  internal;
  proxy_pass http://ticket-resolver.platform.svc.cluster.local/resolve;
  proxy_set_header X-Ticket $arg_ticket;
  proxy_set_header X-Tab    $arg_tab;
  proxy_pass_request_body off;
  proxy_set_header Content-Length "";
}

location = /connect {
  auth_request /_ticket_resolve;
  auth_request_set $tenant_ns   $upstream_http_x_tenant_ns;
  auth_request_set $service_id  $upstream_http_x_service_id;
  auth_request_set $tab_id      $upstream_http_x_tab_id;
  auth_request_set $session_tok $upstream_http_x_session_token;

  if ($tenant_ns = "") { return 403; }

  # namespace名の形式検証(RFC1123ラベル)。不正値をproxy_passに使わせない防御
  if ($tenant_ns !~ "^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$") { return 400; }

  # 接続確立後はCookieでセッションを維持し、以降ticketなしでも再訪できるようにする
  add_header Set-Cookie "tn_session=$session_tok; Path=/; HttpOnly; Secure; SameSite=Strict; Max-Age=28800";

  # クライアント由来のヘッダーは必ず一度破棄してから確定値で上書きする
  proxy_set_header X-Tenant-Id  "";
  proxy_set_header X-Service-Id "";
  proxy_set_header X-Tab-Id     "";
  proxy_set_header X-Tenant-Id  $tenant_ns;
  proxy_set_header X-Service-Id $service_id;
  proxy_set_header X-Tab-Id     $tab_id;

  proxy_pass http://envoy.$tenant_ns.svc.cluster.local;
}
```

### 7.2 2回目以降のリクエスト(Cookieベース解決)

```nginx
location / {
  # Cookieのtn_sessionからtenant_nsを解決(こちらもauth_requestで検証)
  auth_request /_session_resolve;
  auth_request_set $tenant_ns   $upstream_http_x_tenant_ns;
  auth_request_set $service_id  $upstream_http_x_service_id;
  auth_request_set $tab_id      $upstream_http_x_tab_id;

  if ($tenant_ns = "") { return 401; }
  if ($tenant_ns !~ "^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$") { return 400; }

  # X-Tab-Id はクライアント(sessionStorage経由)からも送られてくるが、
  # 「どのtenant_nsに属するtab_idか」はサーバー側(Redis)の記録が正である。
  # クライアント申告のX-Tab-Idは _session_resolve 側で突合済みなので、
  # ここでも念のため上書きする。
  proxy_set_header X-Tenant-Id  "";
  proxy_set_header X-Service-Id "";
  proxy_set_header X-Tab-Id     "";
  proxy_set_header X-Tenant-Id  $tenant_ns;
  proxy_set_header X-Service-Id $service_id;
  proxy_set_header X-Tab-Id     $tab_id;

  proxy_pass http://envoy.$tenant_ns.svc.cluster.local;
}

location = /_session_resolve {
  internal;
  proxy_pass http://ticket-resolver.platform.svc.cluster.local/session;
  proxy_set_header Cookie      $http_cookie;
  proxy_set_header X-Tab-Id-In $http_x_tab_id;   # クライアント申告値(検証対象として渡す)
  proxy_pass_request_body off;
  proxy_set_header Content-Length "";
}
```

### 7.3 tn_sessionの位置づけ

`tn_session` Cookieは、**「この接続で確定したtenant_ns」をnginx ingress自身が保証するための内部Cookie**であり、ポータルの認証セッションCookieとは別物として扱う(名前空間の混同を避けるため`tn_`プレフィックスを付与)。1接続(=1タブ)につき1つ発行され、`tab_id`とセットでRedis上に記録されるため、複数タブを開いても互いに干渉しない(3節の全体アーキテクチャ参照)。

---

## 8. Envoyルーティング仕様

Hostは一切参照せず、`x-service-id`ヘッダーのみでcluster選択を行う。

```yaml
static_resources:
  listeners:
    - name: listener_0
      filter_chains:
        - filters:
            - name: envoy.filters.network.http_connection_manager
              typed_config:
                "@type": type.googleapis.com/envoy.extensions.filters.network.http_connection_manager.v3.HttpConnectionManager
                route_config:
                  name: local_route
                  virtual_hosts:
                    - name: tenant_vhost
                      domains: ["*"]
                      routes:
                        - match:
                            prefix: "/"
                            headers:
                              - name: x-service-id
                                string_match: { exact: "web1" }
                          route:
                            cluster: web1_cluster
                        - match:
                            prefix: "/"
                            headers:
                              - name: x-service-id
                                string_match: { exact: "web2" }
                          route:
                            cluster: web2_cluster
                        - match:
                            prefix: "/"
                            headers:
                              - name: x-service-id
                                string_match: { exact: "web3" }
                          route:
                            cluster: web3_cluster
                        - match:
                            prefix: "/"
                          direct_response:
                            status: 400
                            body: { inline_string: "unknown service_id" }
```

`X-Tenant-Id` / `X-Tab-Id`はルーティング判断には使わず、下流(Web1/2/3)へそのまま透過する(Envoyはデフォルトで未加工のヘッダーを透過するため追加設定不要)。

---

## 9. クライアント側(SPA)実装仕様

### 9.1 Portal側: 接続開始

```javascript
// Portal(React+MUI)側 - テナント接続ボタンのハンドラ
async function connectToTenant(tenantId, serviceId) {
  const tabId = crypto.randomUUID();

  const res = await fetch("/api/connections", {
    method: "POST",
    credentials: "include", // ポータルセッションCookieを送る
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ tenant_id: tenantId, service_id: serviceId, tab_id: tabId }),
  });

  if (!res.ok) {
    throw new Error(`connection failed: ${res.status}`);
  }

  const { connect_url } = await res.json();
  window.open(connect_url, `tenant-${tenantId}-${tabId}`);
}
```

### 9.2 テナントWebアプリ側: 初期化

```javascript
// テナントWebアプリ(Web1/2/3)側 - 起動時に一度だけ実行
(function initTenantContext() {
  const params = new URLSearchParams(location.search);
  const tabIdFromUrl = params.get("tab");

  if (tabIdFromUrl) {
    sessionStorage.setItem("tab_id", tabIdFromUrl);
    // ticketは使い捨てのためURLから除去し、tn_session Cookieに以後の解決を委ねる
    const cleanUrl = `${location.origin}${location.pathname}`;
    history.replaceState({}, "", cleanUrl);
  }
})();
```

### 9.3 API呼び出し時のヘッダー付与

```javascript
// axios interceptor例
axiosInstance.interceptors.request.use((config) => {
  const tabId = sessionStorage.getItem("tab_id");
  if (tabId) {
    config.headers["X-Tab-Id"] = tabId;
  }
  // credentials: withCredentials相当を有効化し、tn_session Cookieを常に送る
  config.withCredentials = true;
  return config;
});
```

クライアントは`X-Tenant-Id`を**自ら送信しない**(送っても7.1/7.2でnginxが必ず上書きするため無害だが、そもそも実装上も持たせない方針とする)。テナントの確定はサーバー側(nginx ingress + tn_session Cookie)の責務であることを、クライアント実装のレベルでも明確にするため。

---

## 10. Web1/2/3(アプリケーション層)実装仕様

### 10.1 JWTクレームとの突合検証(共通ミドルウェア方針)

`X-Tenant-Id`はnginx ingressが確定した値だが、経路上の設定ミス・バグへの防御として、Cognito JWTの`custom:tenant_id`クレームと必ず突合する。

```python
# Flask/Django共通で使えるミドルウェアの実装イメージ(Flask版)
from functools import wraps
from flask import request, abort, g

def verify_tenant_header(f):
    @wraps(f)
    def wrapper(*args, **kwargs):
        header_tenant = request.headers.get("X-Tenant-Id")
        jwt_claims = decode_and_verify_jwt(request.headers.get("Authorization"))

        if not header_tenant or not jwt_claims:
            abort(401)

        if header_tenant != jwt_claims.get("custom:tenant_id"):
            # ルーティング層とJWTの不一致 = 設定ミス or 改ざんの兆候
            log_security_event(
                "tenant_header_mismatch",
                header_tenant=header_tenant,
                jwt_tenant=jwt_claims.get("custom:tenant_id"),
            )
            abort(403)

        g.tenant_id = header_tenant
        return f(*args, **kwargs)
    return wrapper
```

```ruby
# Rails8版(ApplicationControllerのbefore_action)
class ApplicationController < ActionController::Base
  before_action :verify_tenant_header

  private

  def verify_tenant_header
    header_tenant = request.headers["X-Tenant-Id"]
    claims = decode_and_verify_jwt(request.headers["Authorization"])

    head :unauthorized and return if header_tenant.blank? || claims.blank?

    if header_tenant != claims["custom:tenant_id"]
      SecurityEventLogger.log(:tenant_header_mismatch,
        header_tenant: header_tenant, jwt_tenant: claims["custom:tenant_id"])
      head :forbidden and return
    end

    @current_tenant_id = header_tenant
  end
end
```

```javascript
// Next.js版(middleware.ts, App Router)
import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";

export function middleware(req: NextRequest) {
  const headerTenant = req.headers.get("x-tenant-id");
  const claims = decodeAndVerifyJwt(req.headers.get("authorization"));

  if (!headerTenant || !claims) {
    return new NextResponse(null, { status: 401 });
  }
  if (headerTenant !== claims["custom:tenant_id"]) {
    logSecurityEvent("tenant_header_mismatch", { headerTenant, jwtTenant: claims["custom:tenant_id"] });
    return new NextResponse(null, { status: 403 });
  }
  return NextResponse.next();
}

export const config = {
  matcher: ["/((?!_next/static|_next/image|favicon.ico).*)"],
};
```

---

## 11. 静的アセット配信の分離仕様

### 11.1 対象パスと配信方針

| パス | 配信元 | ticket/tenant解決 |
|---|---|---|
| `/assets/*`(Rails+Vite) | 共有配信ホスト(専用podまたはS3+CloudFront) | 不要 |
| `/static/*`(Django collectstatic) | 同上 | 不要 |
| `/_next/static/*` | 同上(`assetPrefix`で明示的に向き先を固定) | 不要 |
| `/_next/data/*` | 通常のテナント振り分け経路 | **必要** |
| `/_next/image` | 通常のテナント振り分け経路 | **必要** |

### 11.2 nginx設定

```nginx
location ~ ^/(_next/static|assets|static)/ {
  proxy_cache tenant_static_cache;
  proxy_cache_valid 200 30d;
  proxy_pass http://static-cache.platform.svc.cluster.local;
}
```

### 11.3 Next.js側のビルド設定

```javascript
// next.config.js(全テナント共通ビルドで単一値でよい)
module.exports = {
  assetPrefix: process.env.NEXT_PUBLIC_ASSET_HOST || "https://static.internal.a-corp.com",
};
```

デプロイパイプラインで`.next/static/`を`static-cache`ホストへ同期する。これによりJSバンドル取得のためにscale-to-zero中のテナントpodを起動する必要がなくなる。

---

## 12. Next.js固有の考慮事項(サマリ)

- `assetPrefix`は全テナント共通の1値でよい(`basePath`と異なりテナントごとの分岐が不要)
- `middleware.ts`のmatcherで`_next/static`等を除外し、静的アセット取得時に不要なJWT検証・auth_requestを発生させない
- `/_next/data/*`(クライアントサイドナビゲーション時のprefetch)は必ずテナント固有経路を通す。共有経路に誤って含めるとテナント間でのデータ混入事故になるため、11章の切り分けを厳守する

---

## 13. セキュリティ考慮事項まとめ

| # | 項目 | 対策 |
|---|---|---|
| 1 | クライアント申告のX-Tenant-Id/X-Service-Id/X-Tab-Idの詐称 | nginx ingressで必ず`proxy_set_header <name> "";`後に確定値で上書き |
| 2 | ticketの推測・総当たり | 128bit以上のランダム値、TTL60秒、one-time use |
| 3 | ticket URLの漏洩(共有・ブックマーク) | TTL失効後は無効。接続確立後はtn_session Cookie(HttpOnly/Secure/SameSite=Strict)に委譲し、URLに恒久的な認証情報を残さない |
| 4 | tenant_ns値をproxy_passのFQDN組み立てに使う際のインジェクション | RFC1123ラベル形式の正規表現バリデーションを必須化 |
| 5 | ルーティング層とアプリ層の不一致(設定ミス・バグ) | 10章のJWTクレーム突合検証を全アプリ共通ミドルウェアとして必須化 |
| 6 | 複数タブでのテナント/セッション混線 | tab_id単位でtn_session Cookieおよびsession_tokenを分離発行(3章・7.3節) |
| 7 | 静的アセット経路の誤ったテナント越境 | `_next/data`等の動的パスを共有経路から明示的に除外(11章) |

---

## 14. 移行計画(段階的ロールアウト案)

1. **フェーズ0**: 現行Hostベースの動作を維持したまま、nginx ingressで`X-Tenant-Id`等のヘッダーを並行して生成・付与するだけの変更を先行投入(既存動作に影響なし)
2. **フェーズ1**: Ticket Resolverサービス・Redisスキーマを新規構築し、`/connect`エンドポイントのみ新方式で稼働させる(ポータル側もこのタイミングで切替)
3. **フェーズ2**: Envoyのルーティングを`domains`ワイルドカード+`header_match`へ切替(Hostサフィックスマッチはフォールバックとして一定期間残す)
4. **フェーズ3**: Web1/2/3側にJWT突合検証ミドルウェアを追加(全テナントへの展開)
5. **フェーズ4**: 静的アセット共有配信経路(11章)を構築し、Next.jsの`assetPrefix`切替を実施
6. **フェーズ5**: HostベースのフォールバックロジックをEnvoy/nginxから撤去し、新方式へ完全移行

各フェーズは独立してロールバック可能な単位とし、フェーズ2・3はテナント単位でのカナリア移行を推奨する。

---

## 15. 未決事項(Open Issues)

- Ticket Resolverサービス自体の可用性設計(Redis障害時のフェイルモード)
- `tn_session` CookieのSameSite属性がポータルとの別オリジン間遷移(window.open)で問題にならないか、実機検証が必要
- 静的アセット共有配信ホストの実体(専用pod常駐 vs S3+CloudFront)は別途コスト比較の上で決定
