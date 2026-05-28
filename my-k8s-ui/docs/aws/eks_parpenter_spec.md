## 9. スケーリング設計（詳細）

---

### 9-1. スケーリングの全体方針

本システムのクラウド化における最重要要件の一つとして、**オンプレでは手動対応していたキャパシティ管理を自動化**し、負荷変動に対して自律的にスケールする構成を採用する。

スケーリングは以下の2層で設計する。

```
┌─────────────────────────────────┐
│  Pod層       HPA                │  ← まずPodが増える
│  (アプリのスケール)               │
├─────────────────────────────────┤
│  ノード層    Karpenter           │  ← Podが乗り切れなくなったらノードが増える
│  (インフラのスケール)             │
└─────────────────────────────────┘
```

---

### 9-2. Podスケーリング（HPA）

#### 基本設定

| 項目 | 設定値 | 備考 |
|------|--------|------|
| 対象リソース | 対象サービスのDeployment | StatefulSetは別途検討 |
| 最小レプリカ数 | **2** | 単一障害点の排除 |
| 最大レプリカ数 | **10** | コスト上限を考慮し確定値を記載 |
| スケールアウト指標 | CPU使用率 **60%** | 後述のカスタムメトリクス併用も可 |
| スケールアウト指標 | メモリ使用率 **70%** | |
| スケールアウト判定時間 | **30秒** | デフォルト値 |
| スケールイン安定化時間 | **300秒** | 急激なスケールインを防ぐ |

#### CFnでの扱い
HPAはK8sリソースのためCFnで管理しない。`kubectl apply`で適用する。

```yaml
# hpa.yaml（仕様書に記載）
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: {{ サービス名 }}-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: {{ サービス名 }}
  minReplicas: 2
  maxReplicas: 10
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 60
    - type: Resource
      resource:
        name: memory
        target:
          type: Utilization
          averageUtilization: 70
  behavior:
    scaleIn:
      stabilizationWindowSeconds: 300
```

#### Requests/Limitsの明記
HPAが正しく動作するために**必ず設定が必要**。以下を確定値で記載する。

| | CPU | Memory |
|-|-----|--------|
| requests | `250m` | `256Mi` |
| limits | `500m` | `512Mi` |

---

### 9-3. ノードスケーリング（Karpenter）

Cluster AutoscalerではなくKarpenterを採用する。

**採用理由：**
- ノード起動速度がCluster Autoscalerより速い（秒単位 vs 分単位）
- インスタンスタイプを柔軟に選択でき、スポットインスタンス活用が容易
- CFnの`AWS::EKS::Addon`として管理可能

#### NodePool設計

```yaml
# karpenter-nodepool.yaml（仕様書に記載）
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: default
spec:
  template:
    spec:
      requirements:
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["spot", "on-demand"]   # Spot優先、フォールバックでOn-Demand
        - key: node.kubernetes.io/instance-category
          operator: In
          values: ["c", "m", "r"]         # コンピュート・汎用・メモリ最適化
        - key: kubernetes.io/arch
          operator: In
          values: ["amd64"]
      nodeClassRef:
        name: default
  limits:
    cpu: "100"                            # クラスタ全体のCPU上限（コスト管理）
    memory: 400Gi
  disruption:
    consolidationPolicy: WhenEmptyOrUnderutilized
    consolidateAfter: 30s                 # 空きノードを30秒後に削除
```

#### EC2NodeClass設計

```yaml
apiVersion: karpenter.k8s.aws/v1
kind: EC2NodeClass
metadata:
  name: default
spec:
  amiSelectorTerms:
    - alias: al2023@latest                # Amazon Linux 2023
  subnetSelectorTerms:
    - tags:
        karpenter.sh/discovery: {{ クラスタ名 }}
  securityGroupSelectorTerms:
    - tags:
        karpenter.sh/discovery: {{ クラスタ名 }}
  role: {{ KarpenterNodeRoleName }}       # CFnのOutputsから参照
```

#### CFnでの管理範囲

| リソース | 管理方法 |
|---------|---------|
| Karpenterインストール | `AWS::EKS::Addon` |
| KarpenterのIAMロール | `AWS::IAM::Role`（CFn管理） |
| NodePool/EC2NodeClass | `kubectl apply`（K8sリソースのため） |

---

### 9-4. スポットインスタンス対応

コスト削減のためスポットインスタンスを優先使用するが、突然の中断に備えた設計を行う。

**対応方針：**

- `PodDisruptionBudget（PDB）`を設定し、同時停止Podを最小化する
- 複数のAZにPodを分散させる（`topologySpreadConstraints`で強制）
- Spot中断通知（2分前）をKarpenterが検知し、自動的にdrainする

```yaml
# pdb.yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: {{ サービス名 }}-pdb
spec:
  minAvailable: 1          # 最低1Pod稼働を保証
  selector:
    matchLabels:
      app: {{ サービス名 }}
```

```yaml
# deployment内に追記
spec:
  template:
    spec:
      topologySpreadConstraints:
        - maxSkew: 1
          topologyKey: topology.kubernetes.io/zone
          whenUnsatisfiable: DoNotSchedule
```

---

### 9-5. スケーリングの監視・アラート

スケーリングが**正しく機能しているかを監視**する設計も仕様書に含める。

| 監視項目 | 閾値 | アクション |
|---------|------|-----------|
| HPAがmaxReplicasに張り付いている | 5分以上 | アラート → maxReplicas見直し |
| PendingのままのPod | 10分以上 | アラート → Karpenter設定確認 |
| ノード数が上限（limits）に到達 | - | アラート → limitsの引き上げ検討 |
| スポットインスタンス中断率 | 30%以上 | On-Demandへの比率変更 |

CloudWatch Container InsightsとCloudWatch Alarmsで実装し、**アラームリソースはCFnで管理する**（`AWS::CloudWatch::Alarm`）。

---

### 9-6. スケーリング設計の確定値チェックリスト

仕様書としてすべて**TBDなしで記載**すべき項目一覧。

- [ ] HPAのmin/maxレプリカ数
- [ ] HPAのCPU/Memoryターゲット値
- [ ] スケールイン安定化時間
- [ ] Pod requests/limits値
- [ ] Karpenterのcpu/memoryリミット
- [ ] 対象インスタンスファミリー
- [ ] Spot/On-Demand比率
- [ ] PDBのminAvailable値
- [ ] CloudWatchアラームの閾値