>`Client`(OAuth Client)登録のためのシードスクリプト/Management APIは未実装です
上記について、この部分のみを追加実装してください。
---
最優先要件は「AWS Cognito Hosted UIへの置き換え時に、ReactおよびRailsのコード変更を最小化すること」です。
OIDC Providerの実装はCognitoに依存しない標準OIDC準拠とし、Cognito固有機能への依存はアダプタ層に限定してください。
設計・実装・レビューのすべてで、この要件を最優先にしてください。
---
実装済コードを前提として
Dockerfile
docker-compose.yml
Kubernetes
を作成してください。
Kubernetesは
Deployment
Service
Ingress
PVC
ConfigMap
Secret
NetworkPolicy
PodDisruptionBudget
Resource
Probe
まで作成してください。
ベストプラクティスでお願いします。

---
---

Client(OAuth Client)登録のManagement APIとシードスクリプトを追加し、続けてDocker/Kubernetes一式を作成します。

## 1. Client Management API の追加実装app.tsにclientsRouterを組み込みます。Continuing with the seed script:package.jsonにseedスクリプト設定を追加します。DIRECTORY_TREE.mdを更新します。## 2. Docker / Kubernetes 一式Deployment.yamlをベストプラクティスに沿って全面的に更新します。k8sリソース一覧をまとめるkustomization.yamlを追加します(デプロイ順序と一覧性のため)。DIRECTORY_TREE.mdとzipを更新します。YAML/TSファイルの構文を軽く検証します。全YAML構文OKです。TypeScriptファイルの構文チェックも行います(ネットワーク制約でパッケージ取得はできないため、Node標準の構文パーサで確認します)。全32ファイルが構文エラーなしで通りました。最新版をZIPにまとめます。# 実装完了

## 1. Client Management API(追加分)

| ファイル | 内容 |
|---|---|
| `src/identity/clients.service.ts` | Client CRUD + シークレットローテーション業務ロジック |
| `src/identity/clients.controller.ts` | zodバリデーション + コントローラ |
| `src/identity/clients.routes.ts` | `/api/v1/clients` ルーティング |
| `prisma/seed.ts` | React用Public Client / 管理者アカウントの初期投入 |

**エンドポイント**: `POST /clients`, `GET /clients`, `GET /clients/:clientId`, `PATCH /clients/:clientId`, `DELETE /clients/:clientId`, `POST /clients/:clientId/secret/rotate`

**設計上の要点**:
- Public Client(`isPublic: true`)は`tokenEndpointAuthMethod: NONE`必須、Confidential Clientは秘密鍵ベース必須という整合性をサービス層で検証(422)。
- クライアントシークレットは**作成時・ローテーション時にのみ平文を一度だけ返却**し、以降はハッシュのみ保持。
- `prisma/seed.ts`は環境変数駆動(`SEED_REACT_CLIENT_ID`等)で、CI/CDでの再現可能なシードを想定。

## 2. Docker / Kubernetes

| ファイル | ポイント |
|---|---|
| `Dockerfile` | 4段階マルチステージ(deps/build/prod-deps/runtime)、非root実行、`dumb-init`によるシグナルハンドリング、`HEALTHCHECK`内蔵 |
| `docker-compose.yml` | アプリ本体 + `migrate`/`seed`用ワンショットコンテナ(profiles活用) |
| `k8s/deployment.yaml` | `securityContext`(非root/readOnlyRootFilesystem/capabilities drop ALL)、startup/readiness/liveness の3種Probe、resources requests/limits、`replicas: 1` + `Recreate`戦略(SQLite制約の明示) |
| `k8s/networkpolicy.yaml` | Ingress: nginx-ingress + Rails Podのみ許可。Egress: DNS + Webhook配信用HTTPS/HTTP限定 |
| `k8s/poddisruptionbudget.yaml` | `minAvailable: 1`(単一レプリカ保護の意図をコメントで明記) |
| `k8s/ingress.yaml` | **OIDC Coreのパスのみ公開**(`/api/v1/*`は意図的に未ルーティング=Management APIは外部非公開) |
| `k8s/serviceaccount.yaml` | `automountServiceAccountToken: false` |
| `k8s/kustomization.yaml` | 一括適用用エントリポイント |

**最優先要件との対応**: Ingressの設計自体で「Reactは標準OIDCエンドポイントのみ、Management APIはRailsからのクラスタ内部通信のみ」という境界をインフラ層に強制しています。

全K8s YAML・docker-compose.ymlは構文検証済み、全32 TypeScriptファイルはNode 22の型除去機能で構文検証済みです(Prismaエンジンバイナリの実行検証はネットワーク制限により未実施のため、`npx prisma generate`はお手元の環境でご確認ください)。

