# ディレクトリ構成

```
oidc-dev-server/
├── package.json
├── tsconfig.json
├── vitest.config.ts
├── .env.example
├── Dockerfile
├── .dockerignore
├── docker-compose.yml
├── TESTING.md
├── LOCAL_HTTPS_SETUP.md
├── PRODUCTION_PARITY.md
├── REMOTE_LAN_ACCESS.md
├── scripts/
│   ├── generate-jwks.ts     # JWKS秘密鍵の生成
│   └── manage_users.rb      # User CRUD操作用の簡易CLI(Ruby)
├── prisma/
│   ├── schema.prisma
│   └── seed.ts
├── k8s/
│   ├── kustomization.yaml
│   ├── serviceaccount.yaml
│   ├── configmap.yaml
│   ├── secret.yaml
│   ├── pvc.yaml
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── ingress.yaml
│   ├── networkpolicy.yaml
│   └── poddisruptionbudget.yaml
└── src/
    ├── server.ts
    ├── config/
    │   └── env.ts
    ├── infra/
    │   ├── persistence/
    │   │   └── prisma-client.ts
    │   └── http/
    │       ├── app.ts
    │       ├── problem-json.ts
    │       └── error-handler.ts
    ├── middleware/
    │   └── validation.ts
    ├── oidc-core/
    │   ├── claims.ts
    │   ├── adapter.ts
    │   ├── interactions.ts
    │   └── provider.ts
    ├── types/
    │   └── oidc-provider.d.ts   # oidc-providerに公式型定義が無いための最小アンビエント宣言
    ├── adapters/
    │   └── cognito-compat/
    │       ├── claims-mapper.ts
    │       └── cloudtrail-event-builder.ts   # 内部イベント -> Cognito CloudTrail/EventBridge形状JSON変換
    ├── auth/
    │   ├── admin-auth.middleware.ts
    │   ├── admin-auth.controller.ts
    │   └── admin-auth.routes.ts
    ├── identity/
    │   ├── users.service.ts
    │   ├── users.controller.ts
    │   ├── users.routes.ts
    │   ├── password.controller.ts
    │   ├── password.routes.ts
    │   ├── groups.service.ts
    │   ├── groups.controller.ts
    │   ├── groups.routes.ts
    │   ├── clients.service.ts
    │   ├── clients.controller.ts
    │   └── clients.routes.ts
    └── webhooks/
        ├── webhooks.service.ts
        ├── webhooks.controller.ts
        ├── webhooks.routes.ts
        ├── dispatcher.ts
        ├── event-publisher.ts
        └── sqs-publisher.ts   # Cognito -> SQS -> Backend 同期パイプラインのシミュレーション用送信
```

## 設計境界(最優先要件との対応)

- `src/oidc-core/*` : 標準OIDC準拠のプロトコルコア。Cognito固有知識を一切持たない。
- `src/adapters/cognito-compat/*` : Cognito固有仕様(クレーム名`cognito:groups`等)を吸収する唯一の場所。
- `src/identity/*`, `src/webhooks/*`, `src/auth/*` : Cognito本番には存在しないManagement API。RailsのPort実装からのみ呼ばれる想定。Reactからの直接呼び出しは禁止。
