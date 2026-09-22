# テナントルーティング仕様書
## tenant-router集約方式(Path Token + Redis Lookup + Reverse Proxy)

- **バージョン**: v0.3(検討用ドラフト)
- **対象**: ポータル(React+MUI SPA) → テナントWebアプリ(Rails8 / Flask / Django / Next.js)接続基盤
- **ステータス**: 検討中(未実装)

### 変更履歴

| version | 変更内容 |
|---|---|
| v0.1 | nginx ingress + auth_request + 独立したTicket Resolverサービスによる多段構成 |
| v0.2 | 「ヘッダーが渡る経路が多いほど、上書き漏れによる詐称リスクが分散する」という指摘を受け、**nginx ingress・Ticket Resolverを単一の`tenant-router`コンポーネントへ統合**。tokenをquery paramからURLパスへ変更。NetworkPolicyによる強制を仕様として明記 |
| v0.3 | kubernetes/ingress-nginxの退役、NGF+njsのRedis接続不可を踏まえ7.2節を更新。envoyのルーティング判断をtenant-router自身へ統合する発展案(7.5節)を追加。実装言語の選定について、技術的堅牢性だけでなくチームの学習コストを踏まえた比較(7.2.1節)を追加し、Node.js・Pythonそれぞれのサンプルコード(7.3.1・7.3.2節)を整備 |

---

## 1. 目的・背景

### 1.1 現行方式の課題(再掲)

現行はワイルドカードサブドメイン(`web-0001-web2.example.com`)のホスト名からnginx ingressがnamespaceを、envoyがサービス名を、それぞれ正規表現で抽出してルーティングしている。AWS移行に伴い、相乗り先ドメインがワイルドカード非対応のため、この方式をそのまま踏襲できない。

### 1.2 v0.1からの設計変更の理由

v0.1では「nginx ingress → (auth_requestサブリクエスト) → Ticket Resolver → nginx ingressがヘッダー確定 → envoy → Web1/2/3」という構成を取っていた。この構成には以下の残存リスクがあった。

- ヘッダーの上書き(`proxy_set_header X-Tenant-Id "";` → 確定値で上書き)を行う`location`ブロックが複数存在し、将来新しい`location`が追加された際に上書きを書き忘れるリスクがある
- envoy・Web1/2/3が「nginx ingress以外からのトラフィックを受け付けない」というNetworkPolicyの強制が明示されておらず、これが欠けている場合はクラスタ内の任意のpodからヘッダー詐称が可能になってしまう

v0.2では、**token解析・Redis参照・reverse proxyを単一プロセス(`tenant-router`)に集約**することで、「上書きを書き忘れる場所」を構造的に1箇所へ収斂させる。

### 1.3 本方式の狙い(v0.2)

- URLの**パス**にtoken(推測不可能なopaque値)を埋め込み、`tenant-router`がこれを唯一の入口として解決する
- `tenant-router`より内側(envoy・Web1/2/3)は、NetworkPolicyにより`tenant-router`以外からの到達を一切禁止する
- ポータルの「1セッションで複数テナントへ同時接続する」要件(`tab_id`)と統合する
- 静的アセット配信をテナント解決の対象外に分離し、不要なコールドスタート(scale-to-zeroからの復帰)を避ける

### 1.4 非対象

- CloudFrontなど追加のエッジ層導入(利用可否未確定のため本仕様では前提としない)
- 認可ポリシー(OPA/Cedar等)の詳細設計(別紙とする)

---

## 2. 用語定義

| 用語 | 定義 |
|---|---|
| tenant_ns | テナントを表すnamespace名(例: `web-0001`) |
| service_id | namespace内のサービス識別子(例: `web1`, `web2`, `web3`) |
| tab_id | ブラウザの1タブ(ブラウジングコンテキスト)を識別する一意な値 |
| token | ポータルが接続開始時に発行する、1回限り・短期TTLの不透明な(opaque)ランダム文字列。URLパスに埋め込まれる。tenant_ns・service_id・tab_id・user_idの組をRedis上で紐付ける |
| tenant-router | token解析・Redis参照・reverse proxyを1プロセスで行う、本方式の中核コンポーネント。旧nginx ingress+Ticket Resolverの役割を統合したもの |
| 信頼境界 | クライアント由来の入力を検証し、以降のコンポーネントが無条件に信頼してよい値へと正規化する地点。本方式では`tenant-router`がこれにあたり、他のいかなるコンポーネントもこの役割を代替してはならない |

---

## 3. 全体アーキテクチャ

```
[Portal SPA]
     │ (1) 接続API呼び出し(Cookie認証)
     ▼
[Portal Backend] ──(2) token発行・Redis保存──▶ [Redis/DynamoDB]
     │ (3) connect URL(パスにtoken埋め込み)を返却
     ▼
window.open("https://app.a-corp.com/t/<token>")
     │
     ▼
┌─────────────────────────────────────────────┐
│              tenant-router                    │  ← 信頼境界はここ1箇所のみ
│  (4) パスからtokenを抽出                       │
│  (5) Redis参照(tenant_ns/service_id/tab_id) │
│  (6) X-Tenant-Id等をこの場で確定・付与        │
│  (7) reverse proxy(1ホップで完結)             │
└─────────────────────────────────────────────┘
     │  ※ NetworkPolicyにより、この矢印以外の
     │    経路でenvoy/Web1-3へは到達不可能とする
     ▼
[Envoy] (8) X-Service-Id のみでルーティング判断(Hostは見ない)
     │
     ▼
[Web1 / Web2 / Web3] (9) JWTクレームとX-Tenant-Idを突合検証(二次防御)
```

**v0.1との違い**: 旧構成では「nginx ingress」と「Ticket Resolver」が別プロセス・別ホップだったため、ヘッダー確定ロジックが分散していた。v0.2では両者を`tenant-router`という1つのデプロイ単位に統合し、reverse proxyまでを同一プロセス内で完結させることで、確定ロジックの所在を一意にする。

---

## 4. シーケンス

```
User          Portal(SPA)      Portal API        Redis          tenant-router     Envoy         Web1/2/3
 │ ボタン押下     │                 │                │                │              │              │
 ├──────────────▶│                 │                │                │              │              │
 │               │ POST /connections                 │                │              │              │
 │               │ (tenant=web-0001, Cookie=session) │                │              │              │
 │               ├────────────────▶│                │                │              │              │
 │               │                 │ token発行      │                │              │              │
 │               │                 ├───────────────▶│                │              │              │
 │               │                 │ (tenant_ns, service_id, user_id, tab_id, TTL=60s)             │
 │               │                 │◀ 保存完了 ─────┤                │              │              │
 │               │ connectUrl 応答  │                │                │              │              │
 │               │◀────────────────┤                │                │              │              │
 │ window.open() │                 │                │                │              │              │
 │◀──────────────┤                 │                │                │              │              │
 │ 新規ウィンドウでGET /t/<token>                    │                │              │              │
 ├────────────────────────────────────────────────────────────────▶│              │              │
 │                                 │                │  token検証・   │              │              │
 │                                 │                │◀─Redis参照──── ┤              │              │
 │                                 │                │  X-Tenant-Id等を確定し、その場でreverse proxy │
 │                                 │                │                ├─────────────▶│              │
 │                                 │                │                │ header_matchでcluster選択   │
 │                                 │                │                │              ├─────────────▶│
 │                                 │                │                │              │ JWT突合検証   │
 │◀──────────────────────────────────────────────── HTML(tn_session Cookie発行、以降tab_idはsessionStorageで管理)
```

---

## 5. Ticket(token)発行API仕様(Portal Backend)

Portal Backend自体の役割はv0.1と同様。connect_urlの形式のみ変更する。

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
  "connect_url": "https://app.a-corp.com/t/8f14e45fceea467e9e97d9a1f4c3b2a1/dashboard",
  "expires_in": 60
}
```

パスの第1セグメント(`/t/<token>/`)にtokenを配置し、それ以降の`dashboard`等はテナントアプリ内の初期表示パスとして扱う(`tenant-router`が`/t/<token>`部分のみを消費し、残りをそのままバックエンドへ転送する)。

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
    tab_id = body.get("tab_id") or secrets.token_urlsafe(16)

    if not user_has_tenant_access(user_id, tenant_id):
        return jsonify(error="forbidden"), 403

    token = secrets.token_hex(16)  # 128bit相当のエントロピー

    redis_client.setex(
        f"token:{token}",
        TICKET_TTL_SECONDS,
        json.dumps({
            "user_id": user_id,
            "tenant_id": tenant_id,
            "service_id": service_id,
            "tab_id": tab_id,
            "issued_at": time.time(),
        }),
    )

    trigger_tenant_wakeup(tenant_id)

    connect_url = f"https://app.a-corp.com/t/{token}"
    return jsonify(connect_url=connect_url, expires_in=TICKET_TTL_SECONDS)
```

---

## 6. URLスキーム定義

### 6.1 接続URL(初回ナビゲーション)

```
https://app.a-corp.com/t/<token>[/<初期表示パス>]
```

| セグメント | 必須 | 説明 |
|---|---|---|
| `t` | ○ | tenant-routerがtoken方式であることを識別する固定プレフィックス |
| `<token>` | ○ | 5章で発行されたワンタイムtoken |
| `<初期表示パス>` | - | 省略時はテナントアプリのルート(`/`)へ |

### 6.2 接続確立後のパス

`tenant-router`は`/t/<token>`部分を消費してから、残りのパスをそのままバックエンドへ転送する(パスプレフィックスを除去してから転送する点は、以前検討したCloudFront Function案・パスベースルーティング案と同じ考え方であり、Web1/2/3側は自分がプレフィックス配下にいることを一切意識しない)。

2回目以降のアクセス(同一タブ内でのリンク遷移・リロード)では、tokenは既に使い捨て済みのため、7.4節の`tn_session` Cookieが解決の主体となる。

### 6.3 静的アセットパス(テナント非依存)

```
/_next/static/*
/assets/*
/static/*
```

これらは`tenant-router`のtoken解決ロジックを通さず、共有配信経路へ振り分ける(11章)。

---

## 7. tenant-router仕様

### 7.1 責務

`tenant-router`は以下を**単一プロセス内**で完結させる、本方式の中核コンポーネントである。

1. リクエストパスからtoken(初回)または`tn_session` Cookie(2回目以降)を抽出
2. Redisを参照し、`tenant_ns` / `service_id` / `tab_id` / `user_id`を取得
3. namespace名の形式検証(RFC1123ラベル)
4. `X-Tenant-Id` / `X-Service-Id` / `X-Tab-Id`ヘッダーを**この場で確定**し、下流へのリクエストに設定する(クライアントからの入力を経由させない)
5. 確定した`tenant_ns`に対応するenvoyエンドポイントへreverse proxyする
6. 初回アクセス時は`tn_session` Cookieを発行する

旧v0.1の「nginx ingress」と「Ticket Resolver」は本コンポーネントに統合され、別プロセス・別ホップとしては存在しない。

### 7.2 実装方式の選択肢

| 方式 | 概要 | 長所 | 短所 |
|---|---|---|---|
| ~~(a) nginx + njs~~ | ~~kubernetes/ingress-nginx(コミュニティ版)にNGINX JavaScriptモジュールを組み込む案~~ | - | **選択不可。下記「重要な前提」を参照** |
| (a') NGF + njs | F5社のNGINX Gateway Fabric(Gateway API実装)の`SnippetsFilter`経由でnjsハンドラを組み込む | Gateway APIへの標準化と両立できる | njsがRedisのRESPプロトコルを話せないため、Redis参照には別途HTTP APIを立てる必要があり、結局多段構成に戻る(詳細は下記補足) |
| (b) 専用リバースプロキシサービス(推奨) | Node.js/Python/Go等で自作した軽量なHTTPリバースプロキシ。token解析・Redis参照・proxyingを通常のアプリケーションコードとして実装する。言語選定は7.2.1節を参照 | ロジックが通常のコードとして書け、単体テスト・監査が容易。手前のIngress/Gateway層の技術選定から独立させられる | 新規コンポーネントとしての運用(デプロイ・監視・耐障害設計)が別途必要 |
| (c) Envoy + ext_authz | Envoy自体をエッジに置き、External Authorizationフィルタで外部の解決サービスを呼び、動的にクラスタを選択する | 既にEnvoyを使っている環境との親和性が高い | 設定が複雑になりやすく、動的アップストリーム選択の実装コストが(b)より高い |

#### 重要な前提: kubernetes/ingress-nginx(コミュニティ版)は選択肢から除外する

2025年11月、Kubernetes SIG NetworkおよびSecurity Response Committeeが**kubernetes/ingress-nginx(コミュニティ版)の退役**を発表し、2026年3月末でベストエフォートメンテナンスを終了、リポジトリはread-onlyでアーカイブされた。以後のセキュリティパッチは一切提供されないため、新規採用は不可、既存利用分も移行対象とすべきである。**現行オンプレ環境で使用している`nginx.ingress.kubernetes.io/*`アノテーション(configuration-snippet等)はこのコミュニティ版の記法であり、今回のAWS移行は本来このIngressコントローラー自体の刷新も合わせて検討すべきタイミングである**(本仕様のスコープを超えるため、15章の未決事項に別途記載する)。

なお、F5社が別コードベースで維持する「F5 NGINX Ingress Controller(NIC)」は今回の退役とは無関係の別プロジェクトとして存続しているが、F5自身がGateway API実装であるNGFを今後の本流として位置付けているため、Ingress API系製品(NIC含む)への長期的な投資優先度は不透明である。

本仕様では**(b)専用リバースプロキシサービス**を推奨方式とする。理由は、token解析・検証・Redis参照・ヘッダー確定という「セキュリティ上最も重要なロジック」を、設定ファイルのDSL(nginx snippet等)ではなく通常のプログラミング言語で記述し、コードレビュー・単体テストの対象にできることに加え、**手前のIngress/Gateway層(ingress-nginxの退役、NGFの発展途上、F5 NICの長期的位置付けの不透明さ)がどう変化しても、tenant-router自体を書き直す必要がない**という独立性を確保できるためである。

#### 補足: NGINX Gateway Fabric(NGF)採用時の検討結果

Kubernetes Gateway APIへの標準化を目的にNGF(NGF自体はOpenRestyではなく素のnginx+njsをベースとしたGateway API実装)の採用を検討する場合、`SnippetsFilter`経由で`js_content`ディレクティブを注入すればnjsハンドラを差し込むこと自体は可能である(NGF公式のサンプルでも、`URLRewrite`フィルタでプレフィックスを剥がしつつnjsハンドラへルーティングする、本仕様と類似のパターンが紹介されている)。

しかし、**njsにはRedisのRESPプロトコルを話すための生ソケットAPIが存在せず**(TCP/UDP向けの`fetch`相当のAPI追加は本稿執筆時点で未実装のfeature requestのまま)、njsから直接Redis参照を行うことができない。回避するには「Redisの手前にHTTP APIを立て`ngx.fetch()`経由で呼ぶ」しかなく、これは実質的にv0.1で廃した「別プロセスの解決サービスを経由する多段構成」への逆戻りとなり、v0.2の設計意図(1プロセスでの解決完結)を満たさない。またNGFの`SnippetsFilter`はデフォルト無効の「上級者向け回避策」と公式に位置づけられており、将来のバージョンで正式なPolicy CRDへの置換により仕様変更を迫られるリスク、および`auth_request`との組み合わせで既知の不具合が報告されている点も踏まえ、**njsへのロジック実装は推奨しない**。

NGF自体の採用(Gateway API標準化)を進めたい場合は、NGFにはtenant-routerのロジックを持たせず、`HTTPRoute`でtenant-router(下記7.3のNode.js/Python/Go実装)を通常のbackend Serviceとして指すに留める構成を推奨する。これによりGateway API標準化のメリットを享受しつつ、コアロジックはnjs/SnippetsFilterの制約から独立させられる。

#### 7.2.1 言語選定における学習コストの考慮

(b)専用リバースプロキシサービスの実装言語として、純粋な技術的堅牢性だけで見ればGo(標準ライブラリ`net/http/httputil.ReverseProxy`がWebSocketアップグレードを含め依存パッケージなしで完結する)が有利である。しかし実際の選定は、**このコンポーネントを継続的に保守するチームの既存スキルセット**を踏まえて判断すべきである。

| 観点 | Node.js | Python | Go |
|---|---|---|---|
| WebSocket(ActionCable等)対応 | `http-proxy-middleware`の`ws: true`で標準対応 | `aiohttp`で自前の中継ループが必要(`httpx`はWS非対応) | 標準ライブラリのみで自動対応 |
| 既存スタックとの親和性 | Next.jsの経験があればJS構文・npm・async/awaitは共通。ただし実行環境(下記参照)は別物 | Rails/Flask/Djangoと同系統言語で、チームの心理的障壁が最も低い | 新規言語の習得が必要。ただしKubernetesエコシステム全体がGoで書かれているため、将来的な資産としての価値はある |
| 学習コストの実質 | 低(下記3点のみ) | 中(WS中継・hop-by-hopヘッダー除去を自前実装する分、コード量が増える) | 高(構文・型システム・エラーハンドリング作法をゼロから習得) |

**Next.js経験はあるがNode.js自体は未経験、という場合の注意点**: Next.jsの`middleware.ts`は通常Edge Runtime(Web標準APIのサブセットのみの制限された実行環境)で動作しており、常駐サーバープロセスとしてのNode.js(今回のtenant-router)とは実行環境が異なる。「リクエストを見て判断する」という発想は流用できるが、以下3点は新規に押さえる必要がある。

1. **例外処理**: フレームワーク(Next.js等)が非同期処理中の例外を握りつぶして500エラーに変換してくれる場合が多いが、生のNode.js(Express)ではasync関数を`try/catch`で囲まないと、最悪プロセス全体がクラッシュし、処理中の他の全リクエストに影響する
2. **graceful shutdown**: K8sが送る`SIGTERM`を受けて、新規接続の受付を止めてから処理中のリクエストの完了を待つ処理を自分で書く必要がある(怠るとデプロイのたびに処理中リクエストが強制切断される)
3. **プロセス全体のクラッシュに対する保険**: `process.on("unhandledRejection", ...)`等で、想定漏れの例外がプロセスを落とさないようにする

これらは実装量としては小さく、JS力・npm・async/awaitという土台が既にあれば数日程度で習得可能な範囲である。したがって、**チームにGo経験者がいない場合、純粋な技術的堅牢性よりも学習コストの低さを優先し、Node.jsを推奨する**。Pythonは既存スタック(Rails/Flask/Django)との親和性が最も高い一方、WebSocket対応のために`aiohttp`での自前実装が必要になる分、実装・保守すべきコード量はNode.jsよりやや多くなる点を踏まえて選定する。

### 7.3 サンプルコード

#### 7.3.1 Node.js実装(Express + http-proxy-middleware + ioredis)

```javascript
const express = require("express");
const cookieParser = require("cookie-parser");
const { createProxyMiddleware } = require("http-proxy-middleware");
const Redis = require("ioredis");

const app = express();
app.use(cookieParser());
const redis = new Redis(process.env.REDIS_URL);

const NAMESPACE_PATTERN = /^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$/;
const TOKEN_PATTERN = /^[0-9a-f]{32}$/;

// tn_session Cookie(接続確立後の再訪用)の署名検証
function verifySessionToken(cookieValue) {
  // HMAC署名付きJWT等での実装を想定(詳細は7.4節)
  return verifyAndDecodeSessionJwt(cookieValue);
}

async function resolveTenant(req, res) {
  const tokenMatch = req.path.match(/^\/t\/([0-9a-f]{32})(\/.*)?$/);

  if (tokenMatch) {
    const token = tokenMatch[1];
    if (!TOKEN_PATTERN.test(token)) {
      const err = new Error("invalid token format");
      err.status = 400;
      throw err;
    }

    const raw = await redis.get(`token:${token}`);
    if (!raw) {
      const err = new Error("token invalid or expired");
      err.status = 403;
      throw err;
    }
    const resolved = JSON.parse(raw);

    // ワンタイム性を強制(取得と同時に即時失効)
    await redis.del(`token:${token}`);

    // 接続確立後のパスへ書き換え(/t/<token>を消費)
    req.url = tokenMatch[2] || "/";

    // 再訪用のtn_session Cookieを発行
    const sessionToken = issueSessionToken(resolved);
    res.cookie("tn_session", sessionToken, {
      httpOnly: true,
      secure: true,
      sameSite: "strict",
      maxAge: 8 * 60 * 60 * 1000,
    });
    return resolved;
  }

  // 2回目以降: tn_session Cookieから解決
  const cookieValue = req.cookies["tn_session"];
  if (!cookieValue) {
    const err = new Error("no active tenant session");
    err.status = 401;
    throw err;
  }
  const resolved = verifySessionToken(cookieValue);
  if (!resolved) {
    const err = new Error("invalid or expired session");
    err.status = 401;
    throw err;
  }
  return resolved;
}

// 学習コスト解説(1): asyncミドルウェアは必ずtry/catchで囲む。
// 囲まないと、ここで発生した例外がプロセスをクラッシュさせうる。
app.use(async (req, res, next) => {
  try {
    const resolved = await resolveTenant(req, res);
    if (!NAMESPACE_PATTERN.test(resolved.tenant_id) || !NAMESPACE_PATTERN.test(resolved.service_id)) {
      return res.status(400).send("invalid tenant namespace");
    }
    // クライアント由来のヘッダーは信用しない: ここで確実に上書きする
    req.headers["x-tenant-id"] = resolved.tenant_id;
    req.headers["x-service-id"] = resolved.service_id;
    req.headers["x-tab-id"] = resolved.tab_id;
    req.tenantNamespace = resolved.tenant_id;
    req.serviceId = resolved.service_id;
    next();
  } catch (err) {
    res.status(err.status || 500).send(err.message || "internal error");
  }
});

app.use(
  createProxyMiddleware({
    // 7.5節の統合案を採用する場合はenvoyを経由せずservice_idへ直接向ける
    router: (req) => `http://${req.serviceId}.${req.tenantNamespace}.svc.cluster.local`,
    changeOrigin: true,
    ws: true, // WebSocket(ActionCable等)もこの1行で標準対応する
  })
);

const server = app.listen(8080);

// 学習コスト解説(2): K8sのSIGTERMを受けて、新規接続を止めてから
// 処理中のリクエストの完了を待つ(graceful shutdown)。
process.on("SIGTERM", () => {
  server.close(() => process.exit(0));
});

// 学習コスト解説(3): 想定漏れの例外でプロセス全体が落ちないための保険。
process.on("unhandledRejection", (err) => {
  console.error("unhandled rejection:", err);
});
```

**設計上のポイント**

- `req.headers["x-tenant-id"] = ...`の代入は、クライアントが同名ヘッダーを送っていた場合でも**必ず上書きされる**(Node.jsのHTTPリクエストオブジェクトはプロパティ代入で確実に上書きになり、nginxの「複数回`proxy_set_header`を呼んで後勝ちにする」という間接的な作法に頼る必要がない)
- tokenはRedisから取得すると同時に`DEL`し、ワンタイム性をコード上で保証する(TTLだけに頼らない)
- namespace名の形式検証は、Redisに保存された値に対しても行う(Redis自体が汚染されるケースへの防御的プログラミング)
- `ws: true`によりWebSocketのアップグレード・双方向中継・接続断のクリーンアップは`http-proxy-middleware`に委譲され、自前実装が不要になる

#### 7.3.2 Python実装(aiohttp)

`httpx`はWebSocketに対応していないため、HTTPとWebSocketの両方をプロキシする本用途では`aiohttp`を選定する。

```python
import asyncio
import json
import re

import aiohttp
import itsdangerous
import redis.asyncio as redis
from aiohttp import web

redis_client = redis.from_url("redis://redis.platform.svc.cluster.local")
signer = itsdangerous.TimestampSigner(secret_key="...")  # tn_session署名用

NAMESPACE_PATTERN = re.compile(r"^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$")
TOKEN_PATTERN = re.compile(r"^/t/([0-9a-f]{32})(/.*)?$")

# hop-by-hopヘッダーはそのまま転送してはいけない(RFC 7230)。
# Node.js/http-proxy-middlewareやEnvoyはこれを標準機能として処理してくれるが、
# 自前実装ではここを明示的に除去する必要がある。
HOP_BY_HOP = {
    "connection", "keep-alive", "proxy-authenticate", "proxy-authorization",
    "te", "trailers", "transfer-encoding", "upgrade",
}


async def resolve_tenant(request: web.Request) -> dict:
    """token(初回)またはtn_session Cookie(再訪)からtenant情報を解決する"""
    m = TOKEN_PATTERN.match(request.path)
    if m:
        token = m.group(1)
        raw = await redis_client.get(f"token:{token}")
        if not raw:
            raise web.HTTPForbidden(text="token invalid or expired")
        await redis_client.delete(f"token:{token}")  # one-time use
        resolved = json.loads(raw)
        resolved["_rewritten_path"] = m.group(2) or "/"
        resolved["_issue_cookie"] = True
        return resolved

    cookie_value = request.cookies.get("tn_session")
    if not cookie_value:
        raise web.HTTPUnauthorized(text="no active tenant session")
    try:
        unsigned = signer.unsign(cookie_value, max_age=8 * 3600)
    except itsdangerous.BadSignature:
        raise web.HTTPUnauthorized(text="invalid session")
    resolved = json.loads(unsigned)
    resolved["_rewritten_path"] = request.path
    resolved["_issue_cookie"] = False
    return resolved


async def proxy_handler(request: web.Request) -> web.StreamResponse:
    resolved = await resolve_tenant(request)
    tenant_ns = resolved["tenant_id"]
    service_id = resolved["service_id"]

    if not NAMESPACE_PATTERN.match(tenant_ns) or not NAMESPACE_PATTERN.match(service_id):
        raise web.HTTPBadRequest(text="invalid tenant/service identifier")

    # 7.5節の統合案を採用する場合はenvoyを経由せずservice_idへ直接向ける
    target_url = f"http://{service_id}.{tenant_ns}.svc.cluster.local{resolved['_rewritten_path']}"
    if request.query_string:
        target_url += f"?{request.query_string}"

    # クライアント由来のヘッダーは一度除去し、確定値で上書きする
    fwd_headers = {k: v for k, v in request.headers.items() if k.lower() not in HOP_BY_HOP}
    fwd_headers["X-Tenant-Id"] = tenant_ns
    fwd_headers["X-Service-Id"] = service_id
    fwd_headers["X-Tab-Id"] = resolved["tab_id"]

    if request.headers.get("Upgrade", "").lower() == "websocket":
        return await proxy_websocket(request, target_url, fwd_headers)

    async with aiohttp.ClientSession() as session:
        async with session.request(
            request.method, target_url, headers=fwd_headers,
            data=request.content, allow_redirects=False,
        ) as backend_resp:
            resp = web.StreamResponse(
                status=backend_resp.status,
                headers={k: v for k, v in backend_resp.headers.items() if k.lower() not in HOP_BY_HOP},
            )
            if resolved.get("_issue_cookie"):
                cookie_value = signer.sign(json.dumps(resolved).encode()).decode()
                resp.set_cookie("tn_session", cookie_value, httponly=True,
                                 secure=True, samesite="Strict", max_age=8 * 3600)
            await resp.prepare(request)
            async for chunk in backend_resp.content.iter_chunked(64 * 1024):
                await resp.write(chunk)
            return resp


async def proxy_websocket(request, target_url, fwd_headers):
    """WebSocketの双方向中継ループ。Node.js版ではhttp-proxy-middlewareの
    `ws: true`が肩代わりしていた部分を、ここでは自前で実装する必要がある。"""
    ws_server = web.WebSocketResponse()
    await ws_server.prepare(request)

    ws_url = target_url.replace("http://", "ws://", 1)
    async with aiohttp.ClientSession() as session:
        async with session.ws_connect(ws_url, headers=fwd_headers) as ws_client:

            async def client_to_backend():
                async for msg in ws_server:
                    if msg.type == aiohttp.WSMsgType.TEXT:
                        await ws_client.send_str(msg.data)
                    elif msg.type == aiohttp.WSMsgType.BINARY:
                        await ws_client.send_bytes(msg.data)

            async def backend_to_client():
                async for msg in ws_client:
                    if msg.type == aiohttp.WSMsgType.TEXT:
                        await ws_server.send_str(msg.data)
                    elif msg.type == aiohttp.WSMsgType.BINARY:
                        await ws_server.send_bytes(msg.data)

            await asyncio.gather(client_to_backend(), backend_to_client())

    return ws_server


app = web.Application()
app.router.add_route("*", "/{tail:.*}", proxy_handler)

if __name__ == "__main__":
    # aiohttp.web.run_appはSIGTERM/SIGINTを受けたgraceful shutdownを標準で行う
    web.run_app(app, port=8080)
```

**設計上のポイント**

- `fwd_headers["X-Tenant-Id"] = ...`は辞書への代入であり、Node.js版と同様に確実な上書きになる
- hop-by-hopヘッダーの除去(`HOP_BY_HOP`集合によるフィルタ)は、Node.js版では`http-proxy-middleware`が内部で自動処理している部分を、ここでは明示的に書く必要がある
- WebSocketの中継は`proxy_websocket`関数で自前実装している。片方の接続が切れた際の後始末は`async with`のコンテキストマネージャがカバーするが、ping/pongによるキープアライブや異常系のタイムアウト設計は別途検証が必要
- `aiohttp.web.run_app`はSIGTERM/SIGINTに対するgraceful shutdownを標準で備えており、Node.js版のように明示的な`process.on("SIGTERM", ...)`の実装は不要

### 7.4 tn_session(接続確立後の再訪)

初回token解決時に、`tenant-router`自身が署名付き(HMAC or JWT)の`tn_session` Cookieを発行し、以降のリクエストはこれで解決する。tokenと違いtn_sessionは使い捨てではなく、TTL(例: 8時間)の範囲で繰り返し使用できる。署名検証は`tenant-router`自身が秘密鍵を持って行うため、Redisへの参照すら不要にできる(ステートレスな検証も選択肢だが、失効・強制ログアウトの即時性を優先するなら、tn_session自体もRedisにセッションIDとして記録し、都度存在確認する設計を推奨する)。

### 7.5 発展案: envoyのルーティング判断をtenant-routerへ統合する

7.1〜7.4節の構成では、tenant-routerがtenant_ns/service_idを確定した後、envoyへ1ホップ転送し、envoyが`X-Service-Id`ヘッダーで二段目のルーティング判断(web1/web2/web3の選択)を行っていた。この判断はtenant-routerが既に保持している情報(tenant_ns・service_id)だけで完結するため、envoyへの転送を経由せず、tenant-router自身が`http://{service_id}.{tenant_ns}.svc.cluster.local`を直接の宛先として算出し、そこへ直接reverse proxyする構成も可能である。

**採用してよい条件**: 現状envoyの用途が「ヘッダーに基づくクラスタ選択」のみであり、リトライ・サーキットブレーカー・アウトライヤー検出・高度な負荷分散等の追加のトラフィック管理機能を利用していないこと。

**採用する場合の変更点**:
- 3章の全体アーキテクチャからenvoyの段が消え、tenant-router→Web1/2/3の1段構成になる
- 8章のNetworkPolicyは、envoyへの到達制限が不要になり、Web1/2/3への到達をtenant-routerのみに制限するだけで完結する(強制すべき境界が1箇所減る)
- Rails ActionCable等、WebSocketを用いる機能がこの経路を通る場合、tenant-router自身がWebSocketのアップグレード処理・双方向中継ループを実装する必要がある。この部分はEnvoyやNode.jsの`http-proxy-middleware`(`ws: true`)が標準機能として提供していたものを自前で肩代わりすることになるため、実装・テスト・障害時の挙動(片方の接続断時のクリーンアップ等)を慎重に検証する
- Python実装の場合、HTTPクライアントに`httpx`ではなく`aiohttp`を選定する必要がある(`httpx`はWebSocket非対応のため)

**留意点**: この統合は「ルーティング判断」と「プロキシの実処理(HTTP/WebSocketの正しいハンドリング、hop-by-hopヘッダーの除去、keep-alive、リトライ等)」を1つのプロセスに集約することを意味する。後者はEnvoyのような成熟した実装が長年かけて解決してきた領域であり、自前実装への置き換えは相応の実装・保守コストを伴う点を踏まえて判断する。

---

## 8. NetworkPolicy仕様(必須要件)

7章で説明した通り、`tenant-router`が確定したヘッダーが「信頼できる」と言えるのは、**envoy・Web1/2/3が`tenant-router`以外からのトラフィックを一切受け付けない**という前提があってこそである。これをKubernetesのNetworkPolicyとして明示的に強制する。

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: envoy-ingress-restriction
  namespace: web-0001   # 各テナントnamespaceに同様のポリシーを適用
spec:
  podSelector:
    matchLabels:
      app: envoy
  policyTypes:
    - Ingress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: platform
          podSelector:
            matchLabels:
              app: tenant-router
      ports:
        - protocol: TCP
          port: 8080
```

このポリシーにより、`platform` namespaceの`tenant-router` pod以外からは、各テナントnamespaceの`envoy`へ到達できなくなる。同様のポリシーをWeb1/2/3のpodにも適用し、「envoyからのみ受け付ける」形にすることで、多段全てにわたって経路を強制する。

**Cilium等eBPFベースのCNIを利用している場合**は、IPアドレスベースではなくServiceAccountのID(SPIFFE/mTLS identity)に基づくL3/L4ポリシーを組めるため、pod再作成によるIP変化に影響されずより堅牢な強制が可能である。既存のCNI選定に応じて詳細を詰める。

---

## 9. Envoyルーティング仕様

v0.1から変更なし。Hostは一切参照せず、`x-service-id`ヘッダーのみでcluster選択を行う。

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

---

## 10. クライアント側(SPA)実装仕様

### 10.1 Portal側: 接続開始

```javascript
async function connectToTenant(tenantId, serviceId) {
  const tabId = crypto.randomUUID();

  const res = await fetch("/api/connections", {
    method: "POST",
    credentials: "include",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ tenant_id: tenantId, service_id: serviceId, tab_id: tabId }),
  });

  if (!res.ok) {
    throw new Error(`connection failed: ${res.status}`);
  }

  const { connect_url } = await res.json();

  // tab_idはtn_session発行後にCookieだけでは判別できないため、
  // クライアント側でもsessionStorageに保持しておく
  const win = window.open(connect_url, `tenant-${tenantId}-${tabId}`);
  win.name = tabId; // 新規ウィンドウのwindow.nameとしても保持(補助的な手段)
}
```

### 10.2 テナントWebアプリ側: 初期化

`tenant-router`がtn_session発行時にtab_idも紐付けているため、クライアント側でtab_idを個別に受け渡す必要は必須ではないが、フロントエンドのログ・デバッグ用途のために`window.name`から補助的に取得しておく。

```javascript
(function initTenantContext() {
  // tenant-routerが発行したtn_session Cookieが主体。
  // window.nameは補助的な参照用(サーバー側の検証には使わない)。
  const tabId = window.name || null;
  if (tabId) {
    sessionStorage.setItem("tab_id_hint", tabId);
  }
})();
```

### 10.3 API呼び出し

```javascript
axiosInstance.interceptors.request.use((config) => {
  config.withCredentials = true; // tn_session Cookieを常に送る
  return config;
});
```

クライアントは`X-Tenant-Id`等のヘッダーを一切送信しない。tenant_ns等の解決は完全にサーバー側(`tenant-router`とtn_session Cookie)の責務とする。

---

## 11. Web1/2/3(アプリケーション層)実装仕様

v0.1からの変更なし。`tenant-router`が確定した`X-Tenant-Id`を、Cognito JWTの`custom:tenant_id`クレームと突合検証する(二次防御)。

```python
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

**この検証の位置づけ(重要)**: 8章のNetworkPolicyが正しく機能している限り、この不一致が発生することは本来ない。この検証は「NetworkPolicyの設定ミスや将来の変更による意図しない経路露出」を検知するための、多層防御(defense in depth)の最後の1枚として維持する。

---

## 12. 静的アセット配信の分離仕様

v0.1から変更なし。`tenant-router`の前段(あるいは`tenant-router`自身のrouter関数内)で、静的アセットパスをtoken解決の対象外として振り分ける。

```javascript
// tenant-router内、token解決ミドルウェアより前に配置
app.use(
  ["/_next/static", "/assets", "/static"],
  createProxyMiddleware({
    target: "http://static-cache.platform.svc.cluster.local",
    changeOrigin: true,
  })
);
```

Next.jsの`assetPrefix`設定、collectstatic済み静的ファイルの扱い等はv0.1と同様(旧仕様書11-12章を参照)。

---

## 13. セキュリティ考慮事項まとめ

| # | 項目 | 対策 |
|---|---|---|
| 1 | クライアント申告のX-Tenant-Id等の詐称 | `tenant-router`のコード上で必ず上書き代入する(7.3節)。設定ファイルのDSLに依存する上書き作法(nginxのproxy_set_header多重呼び出し等)より、通常のコードとして書けるため見落としにくい |
| 2 | tokenの推測・総当たり | 128bit相当のランダム値、TTL60秒、Redisからの取得と同時に`DEL`してone-time useをコードレベルで保証 |
| 3 | tenant-router以外の経路からのenvoy/Web1-3への直接到達 | 8章のNetworkPolicyで強制。**本方式全体の安全性はこのNetworkPolicyの正しさに全面的に依存する**ため、最優先で検証・監査対象とする |
| 4 | tenant_ns値をproxyのtarget決定に使う際のインジェクション | RFC1123ラベル形式の正規表現バリデーションを必須化(7.3節) |
| 5 | tenant-router自体の実装バグ | 通常のアプリケーションコードとして単体テストの対象にする(nginx snippetのように設定ファイル内でロジックを組むより、テスト容易性が高い) |
| 6 | 複数タブでのテナント/セッション混線 | tn_session Cookieはtoken解決の都度、新規に発行される。tab_id単位での分離はRedis上の記録(5.3節)に基づく |
| 7 | 万一ヘッダーが詐称された場合の実被害範囲 | Silo型デプロイのため、Web1/2/3自身のDB接続情報は自podのnamespaceに固定されている。ヘッダー詐称が成立しても、他テナントのデータへの到達は別途DB層の認証情報漏洩がない限り発生しない(11章参照)。ただしJWT突合検証によるアラートの信頼性が下がる点は看過できないため、8章のNetworkPolicyを主たる防御として扱う |
| 8 | 静的アセット経路の誤ったテナント越境 | `_next/data`等の動的パスを共有経路から明示的に除外(12章) |

---

## 14. 移行計画(段階的ロールアウト案)

1. **フェーズ0**: `tenant-router`をプロトタイプとして実装し、単体テスト・簡易な負荷試験を実施(本番トラフィックには接続しない)
2. **フェーズ1**: 8章のNetworkPolicyを先行して適用し、現在は「実質的に無くても動いてしまう」防御を先に強制する(既存のHostベース構成に対しても適用可能な範囲で先行導入)
3. **フェーズ2**: Portal Backendのticket発行APIをtenant-router向けの形式(パス埋め込み)に対応させ、一部テナントでカナリア移行
4. **フェーズ3**: Envoyのルーティングを`domains`ワイルドカード+`header_match`へ切替
5. **フェーズ4**: Web1/2/3側にJWT突合検証ミドルウェアを追加(全テナントへ展開)
6. **フェーズ5**: 静的アセット共有配信経路を構築
7. **フェーズ6**: 旧nginx ingress(Hostベース)構成を撤去し、`tenant-router`への完全移行を完了

---

## 15. 未決事項(Open Issues)

- `tenant-router`自体の可用性設計(Redis障害時のフェイルモード、水平スケール時のセッション整合性)
- `tn_session`をステートレス(署名検証のみ)にするか、ステートフル(Redis記録+都度存在確認)にするかの最終決定(即時失効の要件次第)
- NetworkPolicyの実効性検証方法(定期的なペネトレーションテスト、あるいはKyverno/OPA Gatekeeper等によるポリシーの継続的検証)
- CNI(Calico/Cilium等)の選定によって8章のNetworkPolicy実装の堅牢性が変わるため、現行CNIの確認が必要
- 静的アセット共有配信ホストの実体(専用pod常駐 vs S3+CloudFront)は別途コスト比較の上で決定
- **現行オンプレ環境のIngressコントローラー刷新**: 現行の`nginx.ingress.kubernetes.io/*`アノテーションはkubernetes/ingress-nginx(コミュニティ版、2026年3月退役済み)の記法であるため、本tenant-router導入と合わせて、あるいは別プロジェクトとして、Ingressコントローラー自体をF5 NGINX Ingress Controller・NGF・Envoy Gateway・Kong等の継続的にメンテナンスされる選択肢へ刷新する計画を別途立てる必要がある(本仕様はtenant-router導入後の手前の層をこれらから独立させる設計としているため、どの選択肢を採ってもtenant-router自体への影響はない)
