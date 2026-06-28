## Rails マルチテナント基盤 — 詳細解説

---

## 1. 全体構造と設計思想

```
リクエスト
    │
    ▼
TenantIsolationMiddleware          ← テナント識別・スレッド注入
    │
    ▼
CognitoJwtVerifier                 ← 認証（RS256/JWKS）
    │
    ▼
BaseController                     ← 認可・エラーハンドリング統一
    │
    ▼
Controller Action
    │
    ├── Service Layer              ← アプリケーションロジック
    │       └── dry-monads Result ← 例外を値として扱う
    │
    ├── Repository Layer           ← ARアダプタ（ポート/アダプタ）
    │
    └── Domain Layer               ← 純粋Rubyドメインモデル
```

DDDの**ポート/アダプタ（ヘキサゴナル）アーキテクチャ**を採用しています。ドメイン層はRailsに依存しておらず、インターフェース（ポート）経由でのみ外部と接続します。

---

## 2. ドメイン層

### 2-1. `Domain::Tenant::Tenant`（集約ルート）

最も重要な設計判断は**不変オブジェクト（Immutable Value Object as Aggregate Root）**です。

```ruby
def activate
  # ❌ self.status = "active"  ← ミュータブルにしない
  # ✅ 新しいインスタンスを返す
  self.class.new(
    id: id,
    status: "active",
    updated_at: Time.current,
    **other_fields
  )
end
```

**なぜか：**
- 状態変化が明示的になり、変更前後の状態が両方参照できる
- テストが副作用なしに書ける
- 並行処理で安全（共有状態を変更しない）
- イベントソーシングへの移行が容易

**状態機械：**
```
provisioning ──activate──→ active ──suspend──→ suspended
     ↑                       │                    │
     └──activate─────────────┘         activate──→┘
                              │
                              └──terminate──→ terminated
                             ↗
               suspended ──┘
```

`can_activate?`, `can_suspend?`, `can_terminate?` が遷移ガードを担い、不正遷移は `InvalidStateTransitionError` を投げます。

### 2-2. `Domain::Tenant::Plan`（値オブジェクト）

```ruby
PLAN_LIMITS = {
  "free"         => { max_users: 5,           api_rate_limit: 100,   sso_enabled: false },
  "enterprise"   => { max_users: Float::INFINITY, api_rate_limit: 10_000, sso_enabled: true }
}
```

プラン制限はコードに閉じており、DBに持たないことで整合性を保証します。`upgradeable_to?` でアップグレード方向のみ許可するビジネスルールを表現しています。

### 2-3. `Domain::Tenant::DatabaseConfig`（値オブジェクト）

AWS と On-prem で接続情報の構造が異なるため、ファクトリメソッドで隠蔽しています：

```ruby
# AWS: 共有RDS上のスキーマ分離
DatabaseConfig.for_aws(tenant_slug: "acme-corp", rds_host: "rds.example.com")
# → host: "rds.example.com", schema: "public", platform: "aws"

# On-prem: Pod毎のDB
DatabaseConfig.for_onprem(tenant_slug: "acme-corp", namespace: "production")
# → host: "postgres-acme-corp.production.svc.cluster.local", platform: "onprem"
```

### 2-4. `TenantRepositoryInterface`（ポート定義）

```ruby
module Domain::Tenant::TenantRepositoryInterface
  def find_by_id(id)   = raise NotImplementedError
  def save(tenant)     = raise NotImplementedError
  # ...
end
```

ドメイン層が「何が必要か」を宣言し、インフラ層（ActiveRecord）がそれを満たす。依存の向きが逆転しています（DIP）。

---

## 3. テナント識別とスレッド分離

### 3-1. `TenantIsolationMiddleware`

すべてのリクエストはここを通過します：

```ruby
def call(env)
  request = ActionDispatch::Request.new(env)
  return @app.call(env) if skip_tenant_resolution?(request)  # /healthcheck 等

  tenant = @tenant_resolver.resolve(request)
  TenantResolver::TenantContext.set(tenant: tenant)
  env["multitenant.tenant"] = tenant

  @app.call(env)
ensure
  TenantResolver::TenantContext.clear  # 必ずクリア（Puma worker再利用対策）
end
```

`ensure` でのクリアが重要です。Pumaはスレッドを再利用するため、クリアしないと前リクエストのテナント情報が残存します。

### 3-2. `TenantResolver::Resolver`（テナント識別の優先順位）

```ruby
def extract_slug(request)
  from_header(request) ||      # 1. X-Tenant-Slug ヘッダ（最優先）
    from_subdomain(request) || # 2. サブドメイン（acme-corp.api.example.com）
    from_jwt_claim(request)    # 3. JWTの custom:tenant_slug クレーム
end
```

サブドメイン解析では予約語（www, api, app, admin）を除外し、誤識別を防いでいます。

### 3-3. `TenantResolver::TenantContext`（スレッドローカル）

```ruby
class << self
  def current_tenant
    Thread.current[:current_tenant]
  end

  def with_tenant(tenant, user: nil)
    previous = current_tenant
    set(tenant: tenant, user: user)
    yield
  ensure
    self.current_tenant = previous  # ネスト呼び出しにも対応
  end
end
```

`Thread.current` はスレッドローカルストレージです。Pumaの各ワーカースレッドが独立したテナントコンテキストを持ちます。

**スレッド安全性のテスト：**

```ruby
it "is thread-safe" do
  t1 = Thread.new { TenantContext.with_tenant(tenant_a) { sleep 0.05; values[:t1] = current_tenant.slug } }
  t2 = Thread.new { sleep 0.01; TenantContext.with_tenant(tenant_b) { values[:t2] = current_tenant.slug } }
  [t1, t2].each(&:join)

  expect(values[:t1]).to eq("thread-a")  # 干渉しない
  expect(values[:t2]).to eq("thread-b")
end
```

---

## 4. データベース分離戦略

### 4-1. プラットフォーム別アーキテクチャ

```
AWS（本番）                          On-prem（K8s）
─────────────────────                ──────────────────────────────
共有RDS PostgreSQL                   Namespace毎にPostgreSQL Pod

  public schema                       postgres-acme-corp (StatefulSet)
  tenant_acme_corp schema    vs.      postgres-beta-inc  (StatefulSet)
  tenant_beta_inc schema              postgres-gamma-ltd (StatefulSet)
  tenant_gamma_ltd schema
```

**AWSはスキーマ分離：**
- コスト効率（単一RDSインスタンス）
- 1000テナントでもDBコネクション数が爆発しない
- RDS Proxy と組み合わせることでさらにスケール可能

**On-premはDB分離：**
- 完全なデータ隔離（スキーマよりも強い保証）
- テナント毎にリソース制限（K8s requests/limits）
- PVCで永続化、StatefulSetで安定したPod名

### 4-2. `ConnectionPoolRegistry`（接続プール管理）

1000テナントに対応するための核心部分です：

```ruby
class ConnectionPoolRegistry
  include Singleton

  MAX_POOLS       = 1200          # 最大プール数
  POOL_EVICTION_TTL = 30.minutes  # アイドル後の退避時間
  CLEANUP_INTERVAL  = 5.minutes   # バックグラウンドクリーンアップ間隔

  def fetch_or_create(config)
    cache_key = build_cache_key(config)  # "host:port:database:username"

    @mutex.synchronize do
      evict_stale_pools! if @pools.size >= MAX_POOLS  # 上限到達時はLRU退避

      @pools[cache_key] ||= build_pool(config)
      @pool_last_used[cache_key] = Time.current
      @pools[cache_key]
    end
  end
```

**ConnectionPool gem** を使用し、各テナントのDB接続をスレッドセーフに管理します。`Mutex` で `@pools` へのアクセスを保護し、バックグラウンドスレッドで30分アイドルのプールを自動解放します。

### 4-3. `ConnectionManager`（テナントDB切替）

```ruby
def with_tenant(tenant, &block)
  raise TenantSuspendedError, tenant.slug if tenant.suspended?
  raise TenantProvisioningError          unless tenant.database_provisioned?

  config = @connection_resolver.resolve(tenant)
  switch_connection(config, tenant.schema_name, &block)
end

def switch_aws_connection(config, schema_name, &block)
  pool = @pool_registry.fetch_or_create(config)
  pool.with_connection do |conn|
    previous_path = conn.schema_search_path
    conn.schema_search_path = schema_name    # PostgreSQL SET search_path
    yield conn
  ensure
    conn.schema_search_path = previous_path  # 必ず復元
  end
end
```

`search_path` の復元も `ensure` で保証します。

### 4-4. `RdsIamAuthenticator`（パスワードレス認証）

```ruby
def generate_token(host:, port:, username:, region:)
  @mutex.synchronize do
    entry = @cache[cache_key]
    return entry[:token] if entry && Time.current < entry[:expires_at]

    # AWS SigV4署名でトークン生成（有効期限15分）
    token = Aws::RDS::AuthTokenGenerator.new(region: region)
                                        .auth_token(...)
    @cache[cache_key] = { token: token, expires_at: Time.current + TOKEN_TTL - 60 }
    token
  end
end
```

IAM認証を有効化すると、パスワードの代わりに有効期限付きトークンを使用。漏洩リスクを大幅に低減できます。

---

## 5. テナントプロビジョニング

### 5-1. `TenantProvisioner`（オーケストレーション）

dry-monads の `Result` 型でエラーフローを明示的に扱います：

```ruby
def provision(slug:, name:, plan:, settings: {})
  return Failure(ConflictError.new("Slug already taken")) if slug_taken?(slug)

  tenant = Domain::Tenant::Tenant.create(slug: slug, name: name, plan: plan)
  saved  = @tenant_repository.save(tenant)

  db_config = @connection_resolver.build_config_for_provisioning(saved)
  result    = @database_provisioner.provision(saved, db_config)

  case result
  in Success(config)
    final = saved.assign_database_config(config).activate
    Success(@tenant_repository.save(final))
  in Failure(error)
    Failure(TenantProvisioningError.new("DB provisioning failed: #{error.message}"))
  end
end
```

`case/in` パターンマッチングで Success/Failure を分岐。例外を使わないため、呼び出し元が必ずエラーを処理する設計になります。

### 5-2. `AwsRdsProvisioner`（スキーマプロビジョニング）

```ruby
def provision(tenant, config)
  schema_name = tenant.schema_name  # "tenant_acme_corp"

  ActiveRecord::Base.connection.transaction do
    create_schema(schema_name)                # CREATE SCHEMA IF NOT EXISTS
    create_tenant_role(config.username, ...)  # CREATE ROLE + GRANT
    run_tenant_migrations(schema_name)        # db/tenant_migrations/ 以下を適用
  end

  Success(config)
end
```

スキーマ名の安全チェック：
```ruby
def safe_schema_name?(name)
  name.match?(/\Atenant_[a-z0-9_]{1,60}\z/)  # SQLインジェクション対策
end
```

### 5-3. `OnpremPostgresProvisioner`（K8s StatefulSetデプロイ）

```ruby
def provision(tenant, config)
  deploy_postgres_statefulset(tenant, namespace)  # PVC付きStatefulSet
  deploy_postgres_service(tenant, namespace)       # ClusterIP Service
  deploy_postgres_secret(tenant, namespace)        # パスワードをSecret化

  wait_for_pod_ready(tenant, namespace)  # readinessProbeがPassするまでポーリング
  run_tenant_migrations(config)          # 新DBにスキーマ適用

  Success(config)
rescue Timeout::Error
  Failure(TenantProvisioningError.new("Pod did not become ready within #{TIMEOUT}s"))
end
```

StatefulSetのマニフェストにはセキュリティコンテキスト（非rootユーザー実行）、リソース制限、readiness/livenessプローブを完備しています。

### 5-4. `ProvisionTenantDatabaseJob`（非同期プロビジョニング）

```ruby
class ProvisionTenantDatabaseJob < ApplicationJob
  queue_as :provisioning           # 専用キュー（最高優先度）
  sidekiq_options retry: 3         # 失敗時は3回リトライ

  def perform(tenant_id)
    tenant = repository.find_by_id(tenant_id)
    return unless tenant                          # 冪等性: テナントが消えていたら何もしない
    return if tenant.database_provisioned?        # 冪等性: 既にプロビジョニング済みならスキップ

    result = db_provisioner.provision(tenant, config)
    case result
    in Success(config)
      repository.save(tenant.assign_database_config(config).activate)
    in Failure(error)
      raise error.message  # Sidekiqにリトライさせる
    end
  end
end
```

---

## 6. 認証（Cognito JWT）

### 6-1. `CognitoJwtVerifier`（検証フロー）

```
トークン受信
    │
    ├─→ ヘッダデコード（kid取得）
    │
    ├─→ JwksCache.fetch(jwks_uri)
    │       └─→ キャッシュHit → 即時返却（TTL: 1時間）
    │           キャッシュMiss → https://cognito-idp.../jwks.json
    │
    ├─→ kid一致のJWK取得 → RSA公開鍵構築
    │
    ├─→ JWT.decode(RS256, 公開鍵, issuer検証, iat検証)
    │
    └─→ クレーム検証（sub, email 必須）
            │
            ├─→ Success(payload)
            └─→ Failure(TokenExpiredError | TokenVerificationError)
```

### 6-2. `JwksCache`（公開鍵キャッシュ）

```ruby
def fetch(uri)
  MUTEX.synchronize do
    entry = @cache[uri]
    return entry[:data] if entry && !expired?(entry)   # キャッシュHit

    data = fetch_from_remote(uri)
    @cache[uri] = { data: data, fetched_at: Time.current }
    data
  end
end
```

Cognitoの公開鍵は頻繁に変わらないため1時間キャッシュし、リクエスト毎のネットワーク往復を回避しています。

---

## 7. APIレイヤー

### 7-1. `BaseController`（横断的関心事）

```ruby
before_action :authenticate!         # JWT検証 → @current_user
before_action :require_active_tenant! # テナント状態確認

rescue_from NotFoundError,            with: :render_not_found
rescue_from ValidationError,          with: :render_unprocessable
rescue_from TenantSuspendedError,     with: :render_tenant_suspended
# ...すべてのドメイン例外を統一ハンドリング
```

コントローラのアクションメソッドは「正常系」のみに集中できます。

### 7-2. エラーレスポンス形式

```json
{
  "error": {
    "code": "TENANT_SUSPENDED",
    "message": "Tenant is suspended: acme-corp",
    "request_id": "abc-123-def",
    "timestamp": "2024-06-01T12:00:00Z"
  }
}
```

`code` フィールドによりクライアントがプログラム的にエラーを識別できます。

### 7-3. 権限制御

```ruby
# 階層構造
system_admin > owner > admin > member > viewer

require_system_admin!  # /admin/* エンドポイント（Cognitoグループ判定）
require_owner!         # テナント所有者のみ
require_admin!         # 管理者以上
```

### 7-4. ページネーション（Pagy）

```ruby
def paginate(collection)
  pagy_instance, records = pagy(collection, items: per_page)
  {
    data: records,
    meta: {
      current_page: pagy_instance.page,
      total_count:  pagy_instance.count,
      total_pages:  pagy_instance.pages
    }
  }
end

def per_page
  [params[:per_page].to_i.clamp(1, 100), 25].max  # 最大100件/ページ
end
```

`MAX_PAGES = 200` と組み合わせることで、最大2万件までAPIアクセスを制限しています。

---

## 8. レート制限（Rack::Attack）

```ruby
# IPアドレス毎: 5分間に300リクエスト
throttle("api/ip", limit: 300, period: 5.minutes) { |req| req.ip }

# テナント毎: 1分間に1000リクエスト（プラン上限と連動可能）
throttle("api/tenant", limit: 1000, period: 1.minute) do |req|
  req.get_header("HTTP_X_TENANT_SLUG")
end

# 管理API: 1分間に60リクエスト（より厳格）
throttle("api/admin/ip", limit: 60, period: 1.minute) do |req|
  req.ip if req.path.start_with?("/api/v1/admin/")
end
```

429レスポンスには `X-RateLimit-Reset` ヘッダを含め、クライアントが次にいつリトライすればよいか分かるようにしています。

---

## 9. テスト戦略

### 9-1. テスト分類と方針

| テスト種別 | 対象 | DB | モック |
|---|---|---|---|
| Domain spec | Entity/Value Object | なし | なし |
| Repository spec | TenantRepository | あり | なし |
| Service spec | Provisioner/Verifier等 | なし | あり |
| Middleware spec | Rack app | なし | あり |
| Request spec | Controller | あり | JWT stub |
| Job spec | Sidekiq jobs | なし | あり |

### 9-2. ドメインテスト（DBなし、高速）

```ruby
RSpec.describe Domain::Tenant::Tenant do
  it "creates with provisioning status" do
    tenant = described_class.create(slug: "acme-corp", name: "Acme", plan: "free")
    expect(tenant.status).to eq("provisioning")
  end

  it "does not mutate on activate" do
    tenant = described_class.create(...)
    activated = tenant.activate
    expect(tenant.status).to eq("provisioning")   # 元は不変
    expect(activated.status).to eq("active")
  end
end
```

### 9-3. サービステスト（すべてモック）

```ruby
RSpec.describe Services::Tenant::TenantProvisioner do
  let(:tenant_repository) { instance_double(Repositories::TenantRepository) }
  let(:database_provisioner) { instance_double(Services::Database::DatabaseProvisioner) }

  before do
    allow(database_provisioner).to receive(:provision).and_return(Success(db_config))
  end

  it "returns Success when provisioning succeeds" do
    result = provisioner.provision(slug: "acme-corp", name: "Acme", plan: "free")
    expect(result).to be_success
  end
end
```

`instance_double` は実際のクラスのインターフェースを検証するため、シグネチャの変更を即座に検出できます。

### 9-4. Cognito認証のstub

```ruby
def stub_cognito_verification(payload: nil, success: true)
  verifier = instance_double(Services::Auth::CognitoJwtVerifier)
  allow(Services::Auth::CognitoJwtVerifier).to receive(:new).and_return(verifier)
  allow(verifier).to receive(:verify).and_return(Success(merged_payload))
  verifier
end
```

Request specでは実際のHTTPS通信なしにJWT検証をシミュレートします。

---

## 10. 1000テナントスケールへの対応

| 課題 | 対応策 |
|---|---|
| DB接続数爆発 | ConnectionPoolRegistry（最大1200プール、LRU退避） |
| 接続プールの枯渇 | RDS Proxy（推奨）またはpool_size=5の分散 |
| テナント識別コスト | TenantContextのスレッドローカル（DBアクセスなし） |
| 公開鍵フェッチ | JwksCache（1時間TTL） |
| プロビジョニング遅延 | Sidekiq非同期ジョブ（provisioningキュー最優先） |
| APIリソース枯渇 | Rack::Attack（IP/テナント二段階スロットリング） |
| ページング上限 | Pagy max_pages=200（最大2万件） |
| スキーマ名衝突 | `tenant_` プレフィックス＋正規表現検証 |

---

## 11. 本番投入チェックリスト

```
認証・認可
  ✅ RS256 JWT検証（JWKS）
  ✅ JWKS 1時間キャッシュ
  ✅ トークン失効（exp/iss検証）
  ✅ system-adminsグループによる管理API保護

データ分離
  ✅ スレッドローカルによるテナントコンテキスト
  ✅ ensure句でのコンテキストクリア
  ✅ スキーマ名の安全性検証（SQLインジェクション対策）
  ✅ ConnectionPool per tenant

可観測性
  ✅ OpenTelemetry（Rails/AR/PG自動計装）
  ✅ 構造化JSONログ（本番）
  ✅ Request ID（全ログ）

セキュリティ
  ✅ Rack::Attack レート制限
  ✅ セキュリティヘッダ（production.rb）
  ✅ force_ssl（production）
  ✅ non-root Docker実行
  ✅ SecretsManager統合（IAM認証対応）
```

## 12. ファイル別詳細解説（全実装の深掘り）

---

### 12-1. `config/application.rb` — アプリケーション設定の中核

```ruby
config.x.tenant.isolation_strategy = ENV.fetch("TENANT_ISOLATION_STRATEGY", "schema")
config.x.tenant.max_pool_size       = ENV.fetch("TENANT_MAX_POOL_SIZE", 5).to_i
config.x.database.platform          = ENV.fetch("PLATFORM", "aws")
config.x.auth.jwt_algorithm         = "RS256"
config.x.auth.token_cache_ttl       = 300
```

`config.x` は Rails の型安全な拡張設定名前空間です。`ENV.fetch` でデフォルト値を持たせつつ、環境変数未設定時の挙動を明示しています。`config.x` への集約により設定の散在を防ぎ、テスト時の差し替えも容易にしています。

`config.api_only = true` により不要なミドルウェア（Cookie、セッション、CSRF等）をすべてスタックから除外します。これだけで起動時間とメモリ使用量が大幅に削減されます。

---

### 12-2. `config/routes.rb` — ルーティング設計

```ruby
namespace :api do
  namespace :v1 do
    namespace :admin do          # /api/v1/admin/* → system admin専用
      resources :tenants do
        member do
          post :suspend
          post :activate
          post :provision_database
        end
      end
    end
    resources :users do          # /api/v1/users/* → テナントスコープ
      collection { get :me }
    end
  end
end
```

**名前空間による関心の分離：**

- `/api/v1/admin/*` はシステム管理者のみアクセス可（Cognitoグループ判定）
- `/api/v1/*` はテナント内の操作（テナントコンテキスト必須）
- バージョン管理（`v1`）により破壊的変更時に `v2` を並行稼働できる

`member` アクションの `suspend`/`activate` は REST の `update` に含めず独立させています。状態遷移は意図を明示するために専用エンドポイントとする設計判断です。

---

### 12-3. `config/database.yml` — 接続設定

```yaml
variables:
  statement_timeout: 10000              # 10秒でクエリ強制終了
  lock_timeout: 5000                    # 5秒でロック待機タイムアウト
  idle_in_transaction_session_timeout: 10000  # 10秒でアイドルトランザクション強制切断
```

これら3つのタイムアウトは本番で必須です。設定なしでは長時間クエリやロック待ちがコネクション枯渇を引き起こします。

```yaml
prepared_statements: false
advisory_locks: false
```

`prepared_statements: false` はコネクションプーリング（PgBouncer/RDS Proxy）と組み合わせる際に必須です。プリペアドステートメントはコネクション固有の状態を持つため、別コネクションにルーティングされると `ERROR: prepared statement "xyz" does not exist` が発生します。

---

### 12-4. `app/domain/tenant/tenant.rb` — ドメインエンティティの設計詳細

#### ファクトリメソッドパターン

```ruby
def self.create(slug:, name:, plan:, settings: {})
  validate_slug!(slug)    # 早期バリデーション
  validate_name!(name)
  validate_plan!(plan)

  new(
    id: SecureRandom.uuid,
    slug: slug.downcase.strip,
    status: "provisioning",          # 初期状態は常にprovisioning
    settings: default_settings.merge(settings),
    created_at: Time.current,
    updated_at: Time.current
  )
end
```

`new` を直接呼ばせず `create` ファクトリを通すことで、不正な状態のエンティティが生成されることを防ぎます。デフォルト設定のマージも忘れず行います。

#### ドメインルールの表現

```ruby
SLUG_FORMAT = /\A[a-z0-9][a-z0-9\-]{1,61}[a-z0-9]\z/
```

このパターンは：
- 先頭と末尾は英数字（ハイフン不可）
- 中間は英数字とハイフン
- 長さ3〜63文字（DNS名の制限に合わせた設計）

DNSサブドメインとして利用することを想定しているため、RFC準拠の制約をドメインオブジェクト自身が持っています。

#### `schema_name` の重要性

```ruby
def schema_name
  "tenant_#{slug.gsub("-", "_")}"
end
```

PostgreSQL のスキーマ名は識別子規則に従い、ハイフンが使えません。`tenant_` プレフィックスは予約語（`public`, `pg_catalog` 等）との衝突を防ぎます。

---

### 12-5. `app/domain/tenant/tenant_repository_interface.rb` — ポート設計

```ruby
module Domain::Tenant::TenantRepositoryInterface
  def find_by_id(id) = raise NotImplementedError
  def find_by_slug(slug) = raise NotImplementedError
  def find_all(page: 1, per_page: 25, filters: {}) = raise NotImplementedError
  def save(tenant) = raise NotImplementedError
  def delete(tenant) = raise NotImplementedError
  def exists_by_slug?(slug) = raise NotImplementedError
  def count_by_status(status) = raise NotImplementedError
end
```

このインターフェースがポート（Port）です。ドメイン層はこれを `include` した具象クラスの存在を知りません。

**SOLID原則との対応：**
- **S（単一責任）**: テナントの永続化だけに集中
- **D（依存性逆転）**: ドメインがARに依存せず、ARがドメインのインターフェースを実装

テストでは `instance_double` で簡単にスタブできます：

```ruby
let(:repo) { instance_double(Repositories::TenantRepository) }
allow(repo).to receive(:find_by_slug).with("acme").and_return(tenant)
```

---

### 12-6. `app/repositories/tenant_repository.rb` — アダプタ実装

#### ドメインオブジェクトへのマッピング

```ruby
def map_to_domain(record)
  database_config = record.database_config.present? ?
    map_database_config(record.database_config) : nil

  Domain::Tenant::Tenant.new(
    id:              record.id,
    slug:            record.slug,
    status:          record.status,
    database_config: database_config,
    # ...
  )
end
```

ActiveRecord オブジェクトをそのままドメイン層に渡さない点が重要です。`TenantRecord`（AR）と `Domain::Tenant::Tenant`（ドメイン）は別クラスで、リポジトリがその変換を担います。これにより：
- ドメイン層がRailsに依存しない
- DBスキーマ変更の影響がリポジトリ内に閉じる

#### フィルター適用

```ruby
def apply_filters(scope, filters)
  scope = scope.where(status: filters[:status])  if filters[:status].present?
  scope = scope.where(plan: filters[:plan])       if filters[:plan].present?
  scope = scope.search_by_name(filters[:name])    if filters[:name].present?
  scope = scope.created_after(filters[:created_after]) if filters[:created_after].present?
  scope
end
```

メソッドチェーンで条件を積み上げるパターンです。`present?` で nil と空文字を同時に弾きます。各フィルターを独立したスコープとして定義しているため、組み合わせが自由です。

#### 冪等な保存

```ruby
def save(tenant)
  record = TenantRecord.find_by(id: tenant.id) || TenantRecord.new(id: tenant.id)
  record.assign_attributes(map_to_attributes(tenant))
  # ...
end
```

`find_or_initialize` パターンで新規作成と更新を統一したインターフェースで扱います。ドメイン層は「保存」とだけ伝え、INSERT か UPDATE かを意識しません。

---

### 12-7. `lib/database_switcher/connection_pool_registry.rb` — スケールの核心

#### シングルトンパターンの理由

```ruby
class ConnectionPoolRegistry
  include Singleton
```

プロセス全体でプールを共有するためにシングルトンにしています。Pumaの各ワーカースレッドが同じレジストリを参照し、テナントごとのプールを使い回します。

#### LRU退避アルゴリズム

```ruby
def evict_stale_pools!
  cutoff = Time.current - POOL_EVICTION_TTL   # 30分前
  stale_keys = @pool_last_used
    .select { |_, used_at| used_at < cutoff }
    .keys

  stale_keys.each do |key|
    pool = @pools.delete(key)
    @pool_last_used.delete(key)
    pool&.shutdown { |conn| conn.disconnect! rescue nil }  # コネクション切断
  end
end
```

`shutdown` にブロックを渡すことで、プール内の全コネクションを適切にクローズします。`rescue nil` はシャットダウン中の例外を無視し、他のプールの退避を妨げないようにしています。

#### バックグラウンドクリーンアップスレッド

```ruby
def schedule_cleanup
  Thread.new do
    loop do
      sleep(CLEANUP_INTERVAL)    # 5分おき
      @mutex.synchronize { evict_stale_pools! }
    rescue StandardError => e
      Rails.logger.error("Pool cleanup error: #{e.message}")
      # エラーでもループを継続する（rescueをloopの内側に置く）
    end
  end
end
```

`rescue` を `loop` の内側に置くことで、クリーンアップ中のエラーがスレッドを終了させません。このデーモンスレッドはプロセスと同期して動作します。

#### Mutex による競合制御

```ruby
@mutex = Mutex.new

def fetch_or_create(config)
  @mutex.synchronize do
    # この中はシリアル実行保証
    evict_stale_pools! if @pools.size >= MAX_POOLS
    @pools[cache_key] ||= build_pool(config)
    @pool_last_used[cache_key] = Time.current
    @pools[cache_key]
  end
end
```

`Mutex#synchronize` でチェックと生成を原子的に実行します。Mutex なしでは「同一テナントへの同時リクエスト」が複数のプールを生成する競合状態（Race Condition）が発生します。

---

### 12-8. `lib/tenant_resolver/resolver.rb` — テナント識別の実装詳細

#### JWT クレームからの抽出（検証なし）

```ruby
def from_jwt_claim(request)
  auth_header = request.headers["Authorization"]
  token = auth_header.sub(/\ABearer\s+/i, "")

  # ⚠️ 署名検証なしでデコード（識別目的のみ）
  payload = JWT.decode(token, nil, false).first
  payload["custom:tenant_slug"] || payload["tenant_slug"]
rescue JWT::DecodeError
  nil
end
```

ここでは **署名検証をしない** ことが意図的な設計です。テナント識別のためだけにスラッグを取り出しており、認証はその後 `BaseController#authenticate!` で行います。悪意あるトークンでテナントを偽っても、DB内の正当なスラッグと照合するため影響はありません。

#### 予約サブドメインの除外

```ruby
def from_subdomain(request)
  host = request.host
  match = host.match(TENANT_SUBDOMAIN_REGEX)   # /\A([a-z0-9...])\./ 
  subdomain = match[1]

  return nil if %w[www api app admin].include?(subdomain)
  subdomain
end
```

`www.api.example.com` を「www テナント」と誤認しないための防御です。将来予約語を追加する際はここを変更します。

---

### 12-9. `app/services/auth/cognito_jwt_verifier.rb` — JWT検証の詳細

#### CLOCK_SKEW_TOLERANCE の意味

```ruby
JWT.decode(
  token, key, true,
  {
    algorithms: [ALGORITHM],
    leeway: CLOCK_SKEW_TOLERANCE   # 30秒
  }
)
```

`leeway: 30` は時刻のズレ許容幅です。クライアントとサーバーのシステム時計が最大30秒ずれていても認証できます。分散システムではNTP同期があっても数秒のズレは発生します。

#### 検証失敗の型別ハンドリング

```ruby
rescue JWT::ExpiredSignature
  Domain::Shared::Errors::TokenExpiredError.new           # クライアントにリフレッシュ促す
rescue JWT::InvalidIssuerError
  Domain::Shared::Errors::TokenVerificationError.new("Invalid issuer")  # 別プールのトークン
rescue JWT::DecodeError => e
  Domain::Shared::Errors::TokenVerificationError.new(e.message)        # 改竄等
```

`TokenExpiredError` と `TokenVerificationError` を分けることで、クライアントが「期限切れ（→リフレッシュ）」と「不正トークン（→再ログイン）」を区別できます。

#### クレーム検証

```ruby
def validate_claims(payload)
  errors = []
  errors << "Missing sub claim"   if payload["sub"].blank?
  errors << "Missing email claim" if payload["email"].blank?
  errors << "Token not for access" if payload["token_use"] &&
                                      !%w[access id].include?(payload["token_use"])

  return Failure(TokenVerificationError.new(errors.join(", "))) if errors.any?
  Success(payload)
end
```

`token_use` の検証は Cognito 固有です。`access` トークンと `id` トークンは用途が異なり、混同するとセキュリティ上の問題が生じます。

---

### 12-10. `app/services/database/aws_rds_provisioner.rb` — RDS詳細

#### テナントロールの作成とGRANT

```ruby
def create_tenant_role(username, schema_name)
  conn = ActiveRecord::Base.connection

  # ロールが存在しない場合のみ作成（冪等性）
  existing = conn.execute(
    "SELECT 1 FROM pg_roles WHERE rolname = #{conn.quote(username)}"
  ).any?

  unless existing
    password = SecureRandom.hex(32)                # 64文字の安全なパスワード
    conn.execute("CREATE ROLE #{conn.quote_column_name(username)} WITH LOGIN PASSWORD #{conn.quote(password)}")
    store_credentials(username, password)          # SecretsManagerへ保管
  end

  # スキーマへのアクセス権付与
  conn.execute("GRANT USAGE ON SCHEMA #{conn.quote_column_name(schema_name)} TO #{conn.quote_column_name(username)}")
  conn.execute("GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA #{conn.quote_column_name(schema_name)} TO #{conn.quote_column_name(username)}")

  # 将来作成されるテーブルにも自動付与（マイグレーション後も有効）
  conn.execute("ALTER DEFAULT PRIVILEGES IN SCHEMA #{conn.quote_column_name(schema_name)} GRANT ALL ON TABLES TO #{conn.quote_column_name(username)}")
  conn.execute("ALTER DEFAULT PRIVILEGES IN SCHEMA #{conn.quote_column_name(schema_name)} GRANT ALL ON SEQUENCES TO #{conn.quote_column_name(username)}")
end
```

`ALTER DEFAULT PRIVILEGES` が重要です。これがないと、マイグレーションで新規テーブルを追加するたびに手動でGRANTが必要になります。

#### テナントマイグレーションの実行

```ruby
def run_tenant_migrations(schema_name)
  Timeout.timeout(MIGRATION_TIMEOUT) do                # 5分でタイムアウト
    ActiveRecord::Base.connection.schema_search_path = schema_name
    ActiveRecord::MigrationContext.new(
      Rails.root.join("db/tenant_migrations").to_s,    # システムDBとは別ディレクトリ
      ActiveRecord::SchemaMigration
    ).migrate
  end
ensure
  ActiveRecord::Base.connection.schema_search_path = "public"  # 必ず復元
end
```

`db/migrate/` はシステムDB（tenants テーブル等）用、`db/tenant_migrations/` はテナントDB（users, audit_logs 等）用と分けています。

---

### 12-11. `app/services/database/onprem_postgres_provisioner.rb` — K8s詳細

#### StatefulSet マニフェストのポイント

```ruby
securityContext: {
  runAsNonRoot: true,
  runAsUser: 999,     # postgresユーザーのUID
  fsGroup: 999        # PVCのグループ権限
}
```

セキュリティコンテキストでroot実行を禁止します。PostgreSQL の公式イメージは UID 999 で実行されます。`fsGroup` でマウントされたボリュームのグループ所有権を設定し、データ読み書きを可能にします。

```ruby
readinessProbe: {
  exec: { command: ["pg_isready", "-U", "tenant_user", "-d", db_name] },
  initialDelaySeconds: 5,
  periodSeconds: 5,
  failureThreshold: 6    # 5秒×6回=最大30秒待機
}
livenessProbe: {
  initialDelaySeconds: 30,  # 起動完了後に開始
  periodSeconds: 10
}
```

`readinessProbe` と `livenessProbe` を分けることが重要です。readiness は「トラフィックを受け入れる準備ができているか」、liveness は「プロセスが生きているか」を確認します。

#### Podレディネス待機

```ruby
def wait_for_pod_ready(tenant, namespace)
  service_name = "postgres-#{tenant.slug}"
  deadline = Time.current + PROVISION_TIMEOUT    # 120秒後

  loop do
    raise Timeout::Error if Time.current > deadline

    break if @k8s_client.statefulset_ready?(name: service_name, namespace: namespace)

    sleep(PROVISION_POLL_INTERVAL)    # 3秒おきにポーリング
  end
end
```

`Timeout::Error` をループで自前管理しています。`Timeout.timeout` ブロックはRubyのスレッド制御に依存するため、DBトランザクション中での使用は避けています。

---

### 12-12. `app/middleware/tenant_isolation_middleware.rb` — ミドルウェアの詳細

#### Rack の基本契約

```ruby
def call(env)
  # env: Rackの環境ハッシュ（リクエスト情報すべて）
  # 戻り値: [status, headers, body]
  [200, {"Content-Type" => "application/json"}, ['{"ok":true}']]
end
```

Rack ミドルウェアは `call(env)` を実装するオブジェクトです。チェーン上の次のアプリ（`@app`）を呼び出すことで処理が続きます。

#### エラーの早期返却

```ruby
rescue Domain::Shared::Errors::TenantNotFoundError => e
  render_error(404, "TENANT_NOT_FOUND", e.message)
  # ← ここでRackレスポンスを直接返す（コントローラに届かない）
rescue Domain::Shared::Errors::TenantSuspendedError => e
  render_error(403, "TENANT_SUSPENDED", e.message)
```

コントローラに到達する前にミドルウェアで弾くため、無効なテナントへのリクエストがルーティングやDB処理のコストを消費しません。

#### `ensure` によるクリーンアップの保証

```ruby
def resolve_and_set_tenant(env, request)
  tenant = @tenant_resolver.resolve(request)
  TenantResolver::TenantContext.set(tenant: tenant)
  @app.call(env)         # ← アプリが例外を投げても
ensure
  TenantResolver::TenantContext.clear  # ← 必ず実行される
end
```

Puma はスレッドプールでワーカーを再利用します。`ensure` がなければ前のリクエストのテナントが次のリクエストに漏れます。

---

### 12-13. `app/controllers/api/v1/base_controller.rb` — コントローラ基底の詳細

#### `rescue_from` の優先順位

```ruby
rescue_from Domain::Shared::Errors::NotFoundError,    with: :render_not_found
rescue_from Domain::Shared::Errors::ValidationError,  with: :render_unprocessable
rescue_from ActiveRecord::RecordNotFound,              with: :render_not_found
```

`rescue_from` は定義順で評価されます。より具体的なクラスを先に定義します。`ActiveRecord::RecordNotFound` も独自エラーと同じハンドラに転送し、エラーレスポンスを統一しています。

#### JWT ペイロードから CurrentUser の構築

```ruby
def build_current_user(payload)
  Api::V1::CurrentUser.new(
    sub:             payload["sub"],
    email:           payload["email"],
    tenant_slug:     payload["custom:tenant_slug"] || payload["tenant_slug"],
    role:            payload["custom:role"] || "member",  # クレームなければデフォルトmember
    cognito_groups:  payload["cognito:groups"] || []
  )
end
```

`custom:` プレフィックスは Cognito のカスタム属性規則です。`cognito:groups` はグループメンバーシップで、システム管理者判定に使用します。

#### ページネーションヘルパー

```ruby
def per_page
  [params[:per_page].to_i.clamp(1, 100), 25].max
end
```

`clamp(1, 100)` で1〜100の範囲に収め、`max(25)` でデフォルトを25件にしています。`params[:per_page]` が nil や文字列でも `to_i` で安全に 0 になり、`max(25)` で25件に補正されます。

---

### 12-14. `app/controllers/api/v1/admin/tenants_controller.rb` — 管理APIの詳細

#### システム管理者専用のテナントスキップ

```ruby
skip_before_action :require_active_tenant!
before_action :require_system_admin!
```

管理APIはテナントコンテキストを必要としません（テナント自体を管理するため）。`require_active_tenant!` をスキップし、代わりに `require_system_admin!` で Cognito グループを確認します。

#### `create` アクションのモナドフロー

```ruby
def create
  result = tenant_provisioner.provision(
    slug: tenant_create_params[:slug],
    name: tenant_create_params[:name],
    plan: tenant_create_params[:plan]
  )

  case result
  in Dry::Monads::Success(tenant)
    render_created(serialize_tenant(tenant))
  in Dry::Monads::Failure(error)
    render_provisioning_error(error)    # エラー型に応じたHTTPステータス
  end
end
```

`case/in` パターンマッチで Success/Failure を型安全に分岐します。Ruby 3.x の rightward assignment と組み合わせることもできますが、可読性のために展開形を採用しています。

#### エラー型に応じたHTTPステータス分岐

```ruby
def render_provisioning_error(error)
  case error
  when Domain::Shared::Errors::ConflictError
    render_conflict(error)             # 409
  when Domain::Shared::Errors::ValidationError
    render_unprocessable(error)        # 422
  else
    render json: error_body("PROVISIONING_ERROR", error.message), status: :unprocessable_entity
  end
end
```

同じ `Failure` でもエラーの型によって HTTP ステータスを変えています。クライアントが 409 と 422 を区別してリトライ戦略を変えられます。

---

### 12-15. `config/initializers/rack_attack.rb` — レート制限の詳細

#### 二段階スロットリング

```
IP レベル（300 req/5min）
    ↓ 通過
テナントレベル（1000 req/min）
    ↓ 通過
管理APIレベル（60 req/min）
```

IP 単独では複数のテナントからのリクエストを合算してしまうため、テナント単位でも制限します。悪意あるテナントが他のテナントへの影響を受けないようにします。

#### 429 レスポンスのカスタム

```ruby
Rack::Attack.throttled_responder = lambda do |request|
  match_data = request.env["rack.attack.match_data"]
  now = match_data[:epoch_time]
  reset_time = now + (match_data[:period] - now % match_data[:period])

  headers = {
    "X-RateLimit-Limit"     => match_data[:limit].to_s,
    "X-RateLimit-Remaining" => "0",
    "X-RateLimit-Reset"     => reset_time.to_s   # Unix タイムスタンプ
  }
  # ...
end
```

`X-RateLimit-Reset` でクライアントに次のウィンドウ開始時刻を伝えます。指数バックオフを実装するクライアントライブラリはこのヘッダを利用します。

---

### 12-16. `spec/` — テスト設計の詳細

#### DatabaseCleaner の設定

```ruby
config.before(:each) do
  DatabaseCleaner.strategy = :transaction   # デフォルト: トランザクションロールバック
end

config.before(:each, :truncation) do
  DatabaseCleaner.strategy = :truncation    # :truncation タグ付きはTRUNCATE
end
```

通常テストはトランザクションロールバックで高速クリーンアップ。外部プロセス（Sidekiq等）が関わるテストは `TRUNCATE` を使います。

#### FactoryBot のトレイト設計

```ruby
factory :tenant_record do
  # デフォルト: active, professional プラン
  trait :provisioning do
    status { "provisioning" }
    database_config { nil }    # プロビジョニング中はDB設定なし
  end

  trait :suspended do
    status { "suspended" }
    suspended_at { 1.day.ago }
  end

  trait :onprem do
    database_config do
      { "platform" => "onprem", "host" => "postgres-#{slug}.default.svc..." }
    end
  end
end
```

トレイトの組み合わせが可能です：

```ruby
create(:tenant_record, :suspended, :enterprise)  # 停止中のエンタープライズテナント
```

#### ドメインオブジェクトのテストヘルパー

```ruby
def create_domain_tenant(slug: "test-tenant", status: "active")
  db_config = Domain::Tenant::DatabaseConfig.for_aws(...)
  Domain::Tenant::Tenant.new(
    id: SecureRandom.uuid,
    slug: slug,
    status: status,
    database_config: status == "active" ? db_config : nil,
    # ...
  )
end
```

`active` 状態のテナントには自動的に `database_config` を付与します。実際の状態機械と同じ制約をテストデータ生成時にも適用しています。

#### Request Spec での Cognito stub

```ruby
def stub_cognito_verification(payload: nil, success: true)
  verifier = instance_double(Services::Auth::CognitoJwtVerifier)
  allow(Services::Auth::CognitoJwtVerifier).to receive(:new).and_return(verifier)
  allow(verifier).to receive(:verify).and_return(Success(merged_payload))
  verifier
end

# 使用側
before do
  stub_cognito_verification(payload: {
    "sub" => "admin-sub-001",
    "cognito:groups" => ["system-admins"]
  })
end
```

実際のHTTPS通信なしでJWT検証をシミュレートします。`instance_double` はメソッドシグネチャを検証するため、`CognitoJwtVerifier` のインターフェース変更時にテストが失敗します。

---

## 13. 設計上の重要な判断とトレードオフ

### 13-1. スキーマ分離 vs データベース分離（AWS）

| | スキーマ分離（採用） | DB分離 |
|---|---|---|
| コスト | 低（1 RDS） | 高（テナント数×RDS） |
| 分離度 | 中（同一DB） | 高（完全分離） |
| 接続数 | 少（プール共有可） | 多（テナント毎） |
| 1000テナント対応 | ✅ | △（コスト高） |
| バックアップ単位 | DB全体 | テナント単位 |

### 13-2. dry-monads の採用

```ruby
# ❌ 例外ベース（問題点）
def provision(...)
  raise ConflictError if slug_taken?   # 呼び出し元が rescue しないと握り潰される
  # ...
end

# ✅ Result 型（採用）
def provision(...)
  return Failure(ConflictError.new(...)) if slug_taken?
  # ...
  Success(tenant)
end

# 呼び出し元は必ず Result を処理する
case provisioner.provision(...)
in Success(tenant) then render_created(...)
in Failure(error)  then render_error(...)
end
```

Result 型は型システムレベルでエラーハンドリングを強制します。`case/in` の網羅性チェックにより、Failure ケースの見落としがコンパイル時（または RuboCop）で検出されます。

### 13-3. 不変ドメインオブジェクト vs ActiveRecord のミュータブルモデル

ドメインオブジェクトは Pure Ruby で不変、ActiveRecord は永続化のみに使用する分離設計です。

```
Domain::Tenant::Tenant  ←── (変換) ──→  TenantRecord (ActiveRecord)
  （不変、ビジネスロジック）              （ミュータブル、永続化）
```

この分離により：
- ドメインロジックのテストにDBが不要
- ActiveRecord の callback 地獄を回避
- スキーマ変更がドメインロジックに影響しない

---

## 14. 未実装の本番要件（拡張ポイント）

### 14-1. テナントマイグレーション管理

現状は `db/tenant_migrations/` を全テナントに一括適用しています。本番では以下が必要です：

```ruby
# テナント毎のマイグレーション履歴追跡
class TenantMigrationRunner
  def migrate_all_tenants
    TenantRecord.active.find_each do |record|
      tenant = repository.find_by_id(record.id)
      connection_manager.with_tenant(tenant) do
        MigrationContext.new("db/tenant_migrations").migrate
      end
    rescue => e
      logger.error("Migration failed for #{record.slug}: #{e.message}")
      # 失敗テナントを記録してスキップ（他テナントのマイグレーションを止めない）
    end
  end
end
```

### 14-2. テナント間データ移行

```ruby
# テナントのスキーマ移動（オンプレ→AWS移行等）
class TenantMigrationService
  def migrate(source_tenant, target_config)
    # 1. sourceからpg_dump
    # 2. targetにrestore
    # 3. DNS/ルーティング切替
    # 4. source削除
  end
end
```

### 14-3. Plan 上限のリアルタイム強制

```ruby
# users_controller.rb の create に追加すべき検証
def enforce_plan_limits!
  plan = Domain::Tenant::Plan.new(current_tenant.plan)
  user_count = UserRecord.active.count

  if user_count >= plan.max_users
    raise Domain::Shared::Errors::ForbiddenError,
          "Plan limit reached: #{user_count}/#{plan.max_users} users"
  end
end
```

現状はプラン制限値を定義しているだけで、API での強制は実装されていません。

### 14-4. テナントイベントの発行

```ruby
# ActiveSupport::Notifications または イベントバス
ActiveSupport::Notifications.instrument("tenant.provisioned", tenant: tenant) do
  # Slackへの通知、課金システムへの連携等
end
```

---

## 15. ディレクトリ構造の完全マップ

```
rails_multitenant/
├── app/
│   ├── controllers/api/v1/
│   │   ├── base_controller.rb         # 認証・認可・エラーハンドリング基底
│   │   ├── current_user.rb            # JWT ペイロードの値オブジェクト
│   │   ├── users_controller.rb        # テナントスコープのユーザー管理
│   │   ├── memberships_controller.rb  # テナントスコープのメンバーシップ
│   │   ├── audit_logs_controller.rb   # 監査ログ閲覧
│   │   ├── errors_controller.rb       # 404/422/500 エラーページ
│   │   └── admin/
│   │       └── tenants_controller.rb  # テナントCRUD（system admin のみ）
│   ├── domain/
│   │   ├── tenant/
│   │   │   ├── tenant.rb              # 集約ルート（不変オブジェクト）
│   │   │   ├── plan.rb                # プラン制限（値オブジェクト）
│   │   │   ├── database_config.rb     # DB接続設定（値オブジェクト）
│   │   │   └── tenant_repository_interface.rb  # ポート定義
│   │   └── shared/
│   │       └── errors.rb              # ドメイン例外階層
│   ├── jobs/
│   │   ├── application_job.rb         # OpenTelemetry around_perform
│   │   └── provision_tenant_database_job.rb  # 非同期DB構築
│   ├── middleware/
│   │   └── tenant_isolation_middleware.rb  # テナント識別・コンテキスト注入
│   ├── models/
│   │   ├── application_record.rb      # AR基底
│   │   ├── tenant_record.rb           # テナントAR（バリデーション・スコープ）
│   │   ├── user_record.rb             # ユーザーAR（テナントDB内）
│   │   ├── membership_record.rb       # メンバーシップAR
│   │   └── audit_log.rb              # 監査ログAR + .record ファクトリ
│   ├── repositories/
│   │   └── tenant_repository.rb       # TenantRepositoryInterface の実装
│   ├── serializers/
│   │   ├── tenant_serializer.rb       # センシティブ情報除去
│   │   └── user_serializer.rb
│   └── services/
│       ├── auth/
│       │   ├── cognito_jwt_verifier.rb  # RS256/JWKS検証
│       │   └── jwks_cache.rb            # 公開鍵キャッシュ（TTL:1h）
│       ├── aws/
│       │   └── secrets_manager_client.rb  # DB認証情報管理
│       ├── database/
│       │   ├── database_provisioner.rb    # プラットフォーム振り分け
│       │   ├── aws_rds_provisioner.rb     # スキーマ/ロール作成
│       │   ├── onprem_postgres_provisioner.rb  # StatefulSet デプロイ
│       │   └── rds_iam_authenticator.rb   # IAM トークン生成
│       ├── kubernetes/
│       │   └── client.rb              # K8s API クライアント
│       └── tenant/
│           └── tenant_provisioner.rb  # テナントライフサイクル管理
├── config/
│   ├── application.rb                 # Rails 設定 + config.x 拡張
│   ├── routes.rb                      # API ルーティング
│   ├── database.yml                   # タイムアウト設定込み
│   ├── puma.rb                        # マルチワーカー設定
│   ├── sidekiq.yml                    # キュー優先度設定
│   ├── environments/
│   │   ├── production.rb             # 構造化ログ・セキュリティヘッダ
│   │   ├── development.rb
│   │   └── test.rb
│   └── initializers/
│       ├── multitenant.rb             # ミドルウェア登録
│       ├── rack_attack.rb             # レート制限ルール
│       ├── opentelemetry.rb           # 分散トレーシング
│       ├── pagy.rb                    # ページネーション設定
│       └── sidekiq.rb                 # Redis 接続設定
├── db/
│   ├── migrate/
│   │   └── *_create_tenants.rb       # システムDB（tenants テーブル）
│   └── tenant_migrations/
│       ├── *_create_tenant_users.rb  # テナントDB（users）
│       ├── *_create_tenant_audit_logs.rb
│       └── *_create_tenant_memberships.rb
├── lib/
│   ├── database_switcher/
│   │   ├── connection_manager.rb     # DB切替ロジック
│   │   ├── connection_pool_registry.rb  # プールLRU管理
│   │   └── connection_resolver.rb    # プラットフォーム設定解決
│   └── tenant_resolver/
│       ├── resolver.rb               # Header/Subdomain/JWT から識別
│       └── tenant_context.rb         # Thread.current スレッドローカル
└── spec/                             # RSpec 100% カバレッジ
    ├── domain/                       # ドメインオブジェクト（DB不要）
    ├── repositories/                 # リポジトリ（DB統合）
    ├── services/                     # サービス（モック）
    ├── middleware/                   # ミドルウェア（Rack::MockRequest）
    ├── controllers/api/v1/           # Request spec（JWT stub）
    ├── jobs/                         # Sidekiq job spec
    ├── models/                       # AR モデル（DB）
    ├── factories/                    # FactoryBot（トレイト設計）
    └── support/
        ├── helpers/
        │   ├── auth_helpers.rb       # Cognito stub
        │   ├── tenant_helpers.rb     # ドメインオブジェクト生成
        │   ├── database_helpers.rb   # Pool/Provisioner stub
        │   └── request_helpers.rb    # json_body / post_json
        └── shared_examples/
            └── api_responses.rb      # 共通期待値
```
