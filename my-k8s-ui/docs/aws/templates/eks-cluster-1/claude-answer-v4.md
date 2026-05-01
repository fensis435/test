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

