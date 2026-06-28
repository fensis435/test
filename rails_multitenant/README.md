# Rails Multitenancy Platform

Production-ready Rails 8 multitenancy foundation with PostgreSQL database-per-tenant isolation.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                      Request Pipeline                           │
│                                                                 │
│  HTTP Request                                                   │
│      │                                                          │
│      ▼                                                          │
│  TenantIsolationMiddleware                                      │
│      │  ┌─────────────────────────────────────────────────┐   │
│      │  │  TenantResolver::Resolver                        │   │
│      │  │  Priority: Header > Subdomain > JWT Claim        │   │
│      │  └─────────────────────────────────────────────────┘   │
│      │                                                          │
│      ▼                                                          │
│  TenantResolver::TenantContext (Thread-local)                   │
│      │                                                          │
│      ▼                                                          │
│  Api::V1::BaseController                                        │
│      │  ┌──────────────────────────────────────────────────┐   │
│      │  │  Services::Auth::CognitoJwtVerifier               │   │
│      │  │  - JWKS cache (TTL: 1h)                           │   │
│      │  │  - RS256 verification                             │   │
│      │  │  - Claims validation                              │   │
│      │  └──────────────────────────────────────────────────┘   │
│      │                                                          │
│      ▼                                                          │
│  Controller Action                                              │
│      │                                                          │
│      ▼                                                          │
│  Services / Repositories / Domain                               │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                  Database Routing (Platform-aware)               │
│                                                                 │
│  AWS (Production)                    On-Prem (K8s)             │
│  ┌────────────────────┐             ┌────────────────────────┐  │
│  │  Shared RDS        │             │  PostgreSQL Pod         │  │
│  │  PostgreSQL        │             │  per Tenant            │  │
│  │                    │             │                        │  │
│  │  Schema isolation  │             │  Database isolation    │  │
│  │  tenant_acme_corp  │             │  postgres-acme-corp    │  │
│  │  tenant_beta_inc   │             │  postgres-beta-inc     │  │
│  └────────────────────┘             └────────────────────────┘  │
│           │                                   │                 │
│           └──────────────┬────────────────────┘                 │
│                          ▼                                       │
│              ConnectionPoolRegistry (Singleton)                  │
│              - LRU eviction after 30min idle                     │
│              - Max 1200 pools                                    │
│              - Background cleanup thread                         │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                     DDD Layer Structure                         │
│                                                                 │
│  Domain Layer (Pure Ruby, no Rails dependencies)               │
│  ├── Domain::Tenant::Tenant         (aggregate root)           │
│  ├── Domain::Tenant::Plan           (value object)             │
│  ├── Domain::Tenant::DatabaseConfig (value object)             │
│  └── Domain::Shared::Errors         (domain errors)            │
│                                                                 │
│  Repository Layer (ActiveRecord adapters)                       │
│  └── Repositories::TenantRepository                            │
│       implements Domain::Tenant::TenantRepositoryInterface      │
│                                                                 │
│  Service Layer (Application logic)                              │
│  ├── Services::Tenant::TenantProvisioner                       │
│  ├── Services::Database::DatabaseProvisioner                   │
│  ├── Services::Database::AwsRdsProvisioner                     │
│  ├── Services::Database::OnpremPostgresProvisioner             │
│  ├── Services::Auth::CognitoJwtVerifier                        │
│  └── Services::Aws::SecretsManagerClient                       │
│                                                                 │
│  Infrastructure Layer                                           │
│  ├── DatabaseSwitcher::ConnectionManager                       │
│  ├── DatabaseSwitcher::ConnectionPoolRegistry                  │
│  ├── DatabaseSwitcher::ConnectionResolver                      │
│  ├── TenantResolver::Resolver                                  │
│  └── TenantResolver::TenantContext                             │
└─────────────────────────────────────────────────────────────────┘
```

## Tenant Lifecycle

```
provisioning → active ⇄ suspended → terminated
```

- **provisioning**: Database is being set up (async via Sidekiq)
- **active**: Fully operational
- **suspended**: Access blocked, data retained (e.g. billing issue)
- **terminated**: Soft-deleted, database scheduled for deprovisioning

## Setup

```bash
cp .env.example .env
# Edit .env with your configuration

bundle install
rails db:create db:migrate

# Development
docker compose -f docker/docker-compose.yml up
```

## Environment Variables

| Variable | Required | Description |
|---|---|---|
| `PLATFORM` | Yes | `aws` or `onprem` |
| `COGNITO_USER_POOL_ID` | Yes | Cognito User Pool ID |
| `RDS_HOST` | AWS only | RDS cluster endpoint |
| `K8S_NAMESPACE` | On-prem only | Kubernetes namespace |
| `USE_IAM_AUTH` | No | `true` to use RDS IAM auth |
| `AWS_SECRETS_MANAGER_ENABLED` | No | `true` to use Secrets Manager |

## Testing

```bash
bundle exec rspec
```

100% coverage enforced via SimpleCov.

## Tenant Resolution Priority

1. `X-Tenant-Slug` HTTP header (highest priority)
2. Subdomain (e.g. `acme-corp.api.example.com`)
3. JWT `custom:tenant_slug` claim

## API Authentication

All endpoints require a valid Cognito JWT in the `Authorization: Bearer <token>` header.

### Roles

| Role | Capabilities |
|---|---|
| `owner` | Full tenant control |
| `admin` | User management, audit logs |
| `member` | Standard access |
| `viewer` | Read-only access |

### System Admin

Users in the `system-admins` Cognito group can access `/api/v1/admin/*` endpoints.

## Scaling Considerations

- Connection pool registry supports up to 1200 concurrent tenant pools
- Stale pools evicted after 30 minutes idle
- Pagy pagination prevents unbounded queries (max 100 items/page, max 200 pages)
- Rack::Attack throttling: 300 req/5min per IP, 1000 req/min per tenant
- Sidekiq queue priorities: `provisioning > critical > default > low`

---
---

## 生成物一覧

**100ファイル / 91 Rubyファイル / 7,833行**

### アーキテクチャ構成

**ドメイン層（Pure Ruby）**
- `Domain::Tenant::Tenant` — 集約ルート。不変オブジェクト、状態遷移はメソッドが新インスタンスを返す
- `Domain::Tenant::Plan` — プラン制限の値オブジェクト（free/starter/professional/enterprise）
- `Domain::Tenant::DatabaseConfig` — DB接続設定の値オブジェクト（AWS/On-prem両対応）
- `Domain::Tenant::TenantRepositoryInterface` — リポジトリポート定義（依存性逆転）
- `Domain::Shared::Errors` — ドメイン例外の階層

**リポジトリ層**
- `Repositories::TenantRepository` — ActiveRecordアダプタ、ドメインオブジェクトへのマッピング

**サービス層**
- `Services::Tenant::TenantProvisioner` — テナントライフサイクル管理（dry-monads Result型）
- `Services::Database::DatabaseProvisioner` — プラットフォーム振り分け（Strategy Pattern）
- `Services::Database::AwsRdsProvisioner` — RDS上のPostgreSQLスキーマ分離
- `Services::Database::OnpremPostgresProvisioner` — K8s StatefulSet per テナント
- `Services::Auth::CognitoJwtVerifier` — RS256/JWKS検証、Failureモナドで安全に返却
- `Services::Aws::SecretsManagerClient` — テナントDB認証情報の暗号化保管

**インフラ層**
- `DatabaseSwitcher::ConnectionPoolRegistry` — シングルトン、最大1200プール、30分でLRU退避
- `DatabaseSwitcher::ConnectionManager` — AWS（スキーマ切替）/ On-prem（別DB接続）の統一インターフェース
- `TenantResolver::TenantContext` — スレッドローカルによるテナントコンテキスト（Sidekiqジョブ安全）

**RSpec（100%カバレッジ強制）**
- ドメインエンティティ、値オブジェクト、エラー
- リポジトリ（DB統合テスト）
- 全サービスクラス（モックで高速・隔離）
- ミドルウェア単体テスト
- コントローラ Request spec（Cognito JWTをstub）
- バックグラウンドジョブspec
- FactoryBot factories、AuthHelpers、TenantHelpers完備
