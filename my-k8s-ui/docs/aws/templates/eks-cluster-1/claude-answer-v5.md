## 今回の修正内容

### ノード構成の整理（最重要）

```
【Before】                        【After】
KarpenterNodeGroup                SystemManagedNodeGroup
  Min=2, Max=4, Desired=2           Min=1, Max=2, Desired=1
  Taint: role=system:NoSchedule     Taint: CriticalAddonsOnly=true:NoSchedule
  (名前が曖昧)                       (標準taint名 — Helmチャートの--tolerations指定と一致)

+ Karpenter NodePool x2
    workload: m/c/rシリーズ spot/on-demand 動的スケール
    compute:  cシリーズ spot優先 計算Job専用
```

| 区分 | 管理方式 | 初期台数 | スケール | 用途 |
|------|---------|---------|---------|------|
| System MNG | Managed Node Group | **1台** | 手動で最大2台 | Karpenter/ArgoCD/ESO/ALB-ctrl/cert-manager/CW-Agent |
| Workload | **Karpenter** | 0台 | 自動オートスケール | Railsアプリ、計算Job |

### IAMロール漏れの修正（`03-iam.yaml`）

| 新規追加ロール | 対応SA | 用途 |
|-------------|--------|------|
| **ESOControllerRole** | external-secrets/external-secrets (他2SA) | Secrets Manager呼び出し |
| **CloudWatchAgentRole** | amazon-cloudwatch/cloudwatch-agent | CWAgent Pod Identity |
| **FluentBitRole** | amazon-cloudwatch/fluent-bit | Fluent Bit Pod Identity |
| ArgoCDBridgeRole | rails-system/rails-bridge-sa | ArgoCD API呼び出し |
| CodeBuildRole / VPCFlowLogRole / CloudTrailCWLogsRole / RDSMonitoringRole | — | 各サービス用 |

### Pod Identity登録の完全化（`deploy.sh`）

`configure_pod_identities()` で登録するSA一覧：

```
karpenter/karpenter
aws-load-balancer/aws-load-balancer-controller
external-secrets/external-secrets                ← 新規
external-secrets/external-secrets-webhook        ← 新規
external-secrets/external-secrets-cert-controller← 新規
argocd/argocd-server
argocd/argocd-application-controller             ← 新規
argocd/argocd-applicationset-controller          ← 新規
amazon-cloudwatch/cloudwatch-agent               ← 新規
amazon-cloudwatch/fluent-bit                     ← 新規
kube-system/ebs-csi-controller-sa
kube-system/efs-csi-controller-sa
rails-system/rails-gui-sa
rails-system/rails-app-sa
rails-system/rails-bridge-sa
```

### ArgoCD install/uninstall 待機パターン（`helm/rails-gui|app/templates/misc.yaml`）

`wait-for-sync.sh` スクリプトがConfigMapとして各namespaceに配置されます。

```
[install]
  Rails Job pre処理
    └─ ArgoCD API POST /applications/{app}/sync
    └─ ポーリング: sync=Synced & health=Healthy まで5秒間隔で確認
    └─ Failed/Error検出時は即エラー終了 (Rails Jobのpost処理はスキップ)
  Rails Job post処理

[uninstall]
  Rails Job pre処理
    └─ ArgoCD API DELETE /applications/{app}?cascade=true
    └─ ポーリング: HTTP 404 が返るまで確認
  Rails Job post処理
```

---
---

## v4 → v5 差分まとめ（19ファイル変更/新規）

### 新規 Helm Chart: `helm/my-mng/` `helm/my-gui/` `helm/my-app/`

各チャートの `aws-resources.yaml` にAWS連携部分のみ生成（アプリコードは既存のため除外）:

| ファイル | 主な内容 |
|---------|---------|
| `my-mng/templates/aws-resources.yaml` | ServiceAccount(my-mng-sa) / EFS PVC / ExternalSecret×3(DB+Cognito+ArgoCDToken) / ClusterRole(ApplicationSet管理) / ALB Ingress×2(my-mng直接+テナント経由) / **ArgoCD待機スクリプト ConfigMap** / NetworkPolicy / HPA / PDB |
| `my-gui/templates/aws-resources.yaml` | ServiceAccount(gui-sa) / EFS PVC / ExternalSecret×2 / cert-manager Certificate / **NGINX Ingress(パス書換)** / **envoy ConfigMap** / HPA / PDB / NetworkPolicy |
| `my-app/templates/aws-resources.yaml` | ServiceAccount(app-sa) / EFS PVC / ExternalSecret / cert-manager Certificate / **HPA(計算量変動対応: scaleUp高速/scaleDown緩慢)** / PDB / NetworkPolicy |

### `argocd/rails-apps.yaml`（全面改訂）

```
AppProject: tenant-workloads    (my-gui/my-app テナント用 — gui-*/app-* namespace)
AppProject: platform            (my-mng + 管理系)
Application: my-mng             (常駐, ArgoCDが初期install+自動upgrade)
ApplicationSet: my-gui-tenants  (list generator — my-mng Jobが要素追加/削除)
ApplicationSet: my-app-tenants  (list generator — my-mng Jobが要素追加/削除)
```

**テナント install/uninstall フロー:**
```
my-mng Job
  → kubectl patch ApplicationSet (elements に namespace追加)
  → ArgoCDがApplication自動生成 → sync
  → ArgoCD API ポーリング (Synced+Healthy まで待機)
  → 完了通知 → Rails post処理

uninstall:
  → kubectl patch ApplicationSet (elements から削除)
  → ArgoCD Applicationが自動削除 (cascade)
  → HTTP 404 になるまでポーリング
```

### `argocd/platform-apps.yaml`（NGINX Ingress追加）

ingress-nginx: `NodePort(30080/30443)` で待ち受け、ALB Target Group がこれを向く。`nginx.ingress.kubernetes.io/rewrite-target` で `/gui-<userId>/(.*) → /$1` に書き換え。

### `cfn/02-security.yaml`（NGINX Ingress SG追加）

`NginxIngressSecurityGroup`: ALB→NGINX通信を許可、NGINX→workerノード通信を許可。

### `cfn/07-cognito-pipeline-ecr-codebuild.yaml`（ECR 3リポジトリ）

`ECRMyMngRepository` / `ECRMyGuiRepository` / `ECRMyAppRepository` の3つに分離。CodeBuildの環境変数も `ECR_MNG_URI` / `ECR_GUI_URI` / `ECR_APP_URI` に更新。
