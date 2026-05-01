まず既存コードと関連スキルを確認します。全体像を把握しました。大きなスコープなので、構造を整理してから実装します。The tools stopped before I could finish writing all files and copying to outputs. Let me present what was created and note what remains.

---

## 生成済みファイルと設計

今回の要件はかなり大規模で複雑なため、新規作成した主要ファイルの構成と設計判断を整理します。

---

### 新規CFNスタック (2本)

**`07-cognito-pipeline-ecr-codebuild.yaml`**
- **CloudTrail** — Cognito APIイベント（WriteOnly）のみキャプチャ → S3保存 + CloudWatch Logs
- **EventBridge Rule** — `AdminCreateUser`, `AdminDeleteUser`, `AdminAddUserToGroup` 等をSQSへルーティング。`InputTransformer`でRailsが必要なフィールドだけに整形
- **SQS** — Rails long polling用キュー（可視性タイムアウト300秒、DLQ付き）
- **Cognito Groups** — `admin`/`developer`/`viewer` の3グループをラベルとして作成（IAMロール非連動）
- **ECR** — Rails本体用 + フロントエンド用の2リポジトリ（KMS暗号化、スキャンON）
- **CodeBuild + CodePipeline** — GitHub commit検出 → Docker build → ECR push → Helm package → GitHubのhelm-chartsリポジトリへpush

**`08-rails-resources.yaml`**
- **RailsPodRole** — SQS消費 / Cognito読み取り / Secrets Manager / ECR pull の Pod Identity
- **ArgoCDBridgeRole** — Rails JobからArgoCD APIを叩くためのSecret取得権限
- **EFS Access Points** — gui用 / app用 / shared(rsync)用の3つ（EBSを使わずEFSのみ = Multi-AZ安全）
- **SSH SidecarのSGルール** — Pod間ポート2222を許可
- **CloudWatch Log Groups** — rails-gui / rails-app / rails-jobs

---

### 設計上のポイント

| 要件 | 実装方針 |
|------|----------|
| **Cognito user変更検出** | CloudTrail→S3→EventBridge→SQSパイプライン。RailsがSQSをlong pollingし、イベントを受信したらCognito APIで詳細取得→自DBを更新 |
| **CognitoグループはラベルのみでIAM非連動** | CFNの`AWS::Cognito::UserPoolGroup`に`RoleArn`を設定しない |
| **EFS only（EBSなし）** | Multi-AZ 2台構成でAZ障害時にPendingにならないようEFS(ReadWriteMany)のみ使用 |
| **Leader Election** | Kubernetes Lease API（`coordination.k8s.io`）を使用。外部依存なし。LeaderのみSQS消費・cronジョブ実行 |
| **rsync SSH sidecar** | cert-managerが`ClusterIssuer(selfsigned)`でECDSAキーペアを発行→Secretとしてマウント。build時の鍵生成・コピー不要 |
| **helm install/uninstall** | 既存Railsジョブ経由(pre/post処理含む)。ArgoCD APIを`ArgoCDBridgeRole`で呼び出しsync実行 |
| **helm upgrade** | ArgoCDが自動検出（CodeBuildがhelm-chartsリポジトリを更新→ArgoCDがauto-sync） |
| **フロントエンドログイン** | Amplify JS v6 + MUI v5のカスタムUI。JWTはメモリ保持（localStorage不使用）。グループはJWTクレームから取得しラベル表示のみ |
| **ACM公開証明書** | 既存`01-base.yaml`の`www.example.com`ワイルドカード証明書をALBに適用（DNS検証） |
| **cert-manager内部SSH鍵** | `selfsigned-cluster-issuer` ClusterIssuerからSelf-signed証明書を発行 |
| **VPC Endpoint** | 既存`05-vpc-endpoints.yaml`がECR/STS/SQS/SM/KMS等をカバー。CodeBuildもVPC内で動作 |

---

### 追加が必要だった作業（ツール制限で未完）

1. `platform/cluster-issuers/` — cert-manager ClusterIssuer YAMLのGitOpsリポジトリ配置用マニフェスト
2. `rails-app` Helmチャート（rails-guiと同構造、app namespaceへのデプロイ）
3. `deploy.sh`への新フェーズ(07/08スタック、cert-managerインストール、Pod Identity追加)の組み込み
4. `argocd/k8s-manifests.yaml`のクラスタconfigMapへの`COGNITO_SQS_QUEUE_URL`追加

続きが必要な箇所は上記4点です。着手しますか？
---
---

全体像を把握。残り4項目を一気に作成します。完成です。合計 **7,723行 / 26ファイル**、全フェーズのバリデーション通過を確認しました。

---

## 今回追加した内容

### 新規CFNスタック

**`07-cognito-pipeline-ecr-codebuild.yaml`**（791行）
- **CloudTrail** — `WriteOnly` + `AdvancedEventSelectors`でCognito APIのみキャプチャ → S3（KMS暗号化）
- **EventBridge Rule** — `AdminCreateUser`/`AdminDeleteUser`/`AdminAddUserToGroup`等6種を`InputTransformer`でRailsが受け取りやすいJSONに変換してSQSへ
- **SQS + DLQ** — Long polling(20秒)、可視性タイムアウト300秒、DLQでメッセージ損失防止
- **Cognito Groups** — `admin`/`developer`/`viewer` をラベルのみで作成（`RoleArn`省略 → IAM非連動）
- **ECR x2** — Railsアプリ用 + フロントエンド用（KMS暗号化、push時スキャン、ライフサイクルポリシー）
- **CodeBuild x2** — アプリビルド + フロントエンドビルド（VPC内動作でVPCエンドポイント経由ECR push）
- **CodePipeline** — CodeStar ConnectionでGitHub commit検出 → 並列ビルド実行

**`08-rails-resources.yaml`**（296行）
- **RailsPodRole** — SQS消費 / Cognito読み取り / SM / ECR pull の Pod Identity
- **ArgoCDBridgeRole** — Rails JobがArgoCD APIを叩くためのSecret取得権限
- **EFS Access Points x3** — `/gui-data` / `/app-data` / `/shared`（EBSを一切使わない）
- **SSH SidecarのSGルール** — ノード間ポート2222許可

### deploy.sh（904行 / 20フェーズ）

新フェーズの追加と既存フェーズの番号整理を完了。特に重要な追加：

```bash
# 新namespace作成時にRailsが呼ぶパターン
./deploy.sh rails-namespace gui <user-id>
./deploy.sh rails-namespace app <project-id>
```

これにより Rails の pre-hook Job が名前空間作成 → Pod Identity関連付け → ExternalSecret配置 → `cluster-config`コピーまで一括実行できます。

### Helm Charts（rails-gui / rails-app）

| 機能 | 実装 |
|------|------|
| EFS PVC | `ReadWriteMany` / `efs-sc` StorageClass（EBSは使用しない） |
| Multi-AZ 2台 | `topologySpreadConstraints` + `podAntiAffinity`でAZ分散を強制 |
| Leader Election | Kubernetes Lease API（`coordination.k8s.io`）でRBACも含め完全実装 |
| rsync SSH sidecar | cert-managerの`Certificate`CRDでECDSAキーペアを自動発行・Secretマウント |
| ArgoCD Application | Helmチャート内に`Application` CRDを同梱。upgrade=ArgoCD自動、install/uninstall=Rails Job経由 |
| NetworkPolicy | ALB/pod間/RDS/EFS/SSH(2222)ポートを最小権限で制御 |

### cert-manager / ArgoCD設定

- `selfsigned-cluster-issuer` → 内部CA(`cluster-internal-ca`) → `internal-ca-issuer` の3層構造
- rsync SSHサーバはこのCAで署名された証明書を使用 → クライアントがホスト鍵を検証可能
- `rails-workloads` AppProjectに`rails-deployer`ロールを定義 → トークンをSecrets Managerに保存 → Rails JobがArgoCD APIをコール
