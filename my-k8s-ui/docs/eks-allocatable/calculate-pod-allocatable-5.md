前回の設計を引き継いで、`NodeProfileEstimator` を **DaemonSet が将来のNodeにスケジュール可能か** まで考慮する形に修正します。

ポイントは、単純に「現在そのNodeにいるDaemonSet Pod」を見るのではなく、

* `nodeSelector`
* `nodeAffinity`
* `taints / tolerations`
* `topologySpreadConstraints`
* Node側の labels / taints
* Karpenter NodePool の候補Nodeとの整合性

を判定して、**そのNodeProfileで将来必要になるDaemonSetリソースだけを差し引く**ことです。

なお `topologySpreadConstraints` は少し特殊で、Pod単体だけでは完全なスケジューリング判定ができません。そのため、今回の実装では「そのTopology domainの候補Nodeになり得るか」を保守的に判定し、厳密なKubernetes schedulerの再現までは行わない方針にします。

## 修正版 `NodeProfileEstimator`

```ruby
module ClusterCapacity
  class NodeProfileEstimator
    EPSILON = 0.000001

    def initialize(
      nodes:,
      pods:,
      nodepool_name: nil,
      nodepool: nil,
      percentile: 25,
      min_nodes: 2
    )
      @nodes = nodes
      @pods = pods
      @nodepool_name = nodepool_name
      @nodepool = nodepool
      @percentile = percentile
      @min_nodes = min_nodes
    end

    def estimate
      selected_nodes = select_candidate_nodes

      raise InsufficientData,
            "Not enough nodes to estimate Node profile" if selected_nodes.size < @min_nodes

      profiles = selected_nodes.map do |node|
        build_profile(node)
      end

      {
        node_count: profiles.size,

        cpu: statistics(
          profiles.map { |profile| profile[:cpu] }
        ),

        memory: statistics(
          profiles.map { |profile| profile[:memory] }
        ),

        pods: statistics(
          profiles.map { |profile| profile[:pods] }
        ),

        profiles: profiles
      }
    end

    def profile
      result = estimate

      {
        cpu: result[:cpu][:value],
        memory: result[:memory][:value],
        pods: result[:pods][:value]
      }
    end

    private

    # ============================================================
    # Candidate Nodes
    # ============================================================

    def select_candidate_nodes
      @nodes.select do |node|
        next false unless ready?(node)
        next false if unschedulable?(node)

        nodepool_match?(node)
      end
    end

    def nodepool_match?(node)
      return true unless @nodepool_name

      nodepool =
        node.dig(
          "metadata",
          "labels",
          "karpenter.sh/nodepool"
        )

      nodepool == @nodepool_name
    end

    # ============================================================
    # Node Profile
    # ============================================================

    def build_profile(node)
      node_name = node.dig("metadata", "name")

      allocatable =
        node.dig("status", "allocatable") || {}

      alloc_cpu =
        Quantity.cpu(
          allocatable["cpu"]
        )

      alloc_memory =
        Quantity.memory(
          allocatable["memory"]
        )

      alloc_pods =
        allocatable.fetch("pods", "0").to_i

      daemonset_pods =
        daemonset_pods_for(node)

      eligible_daemonset_pods =
        daemonset_pods.select do |pod|
          daemonset_pod_eligible_on_node?(
            pod,
            node
          )
        end

      daemonset_resources =
        daemonset_resources(
          eligible_daemonset_pods
        )

      effective_cpu =
        [
          alloc_cpu - daemonset_resources[:cpu],
          0
        ].max

      effective_memory =
        [
          alloc_memory - daemonset_resources[:memory],
          0
        ].max

      effective_pods =
        [
          alloc_pods - daemonset_resources[:pods],
          0
        ].max

      {
        node: node_name,

        allocatable: {
          cpu: alloc_cpu,
          memory: alloc_memory,
          pods: alloc_pods
        },

        daemonset: {
          cpu: daemonset_resources[:cpu],
          memory: daemonset_resources[:memory],
          pods: daemonset_resources[:pods]
        },

        effective: {
          cpu: effective_cpu,
          memory: effective_memory,
          pods: effective_pods
        },

        cpu: effective_cpu,
        memory: effective_memory,
        pods: effective_pods
      }
    end

    # ============================================================
    # DaemonSet Pods
    # ============================================================

    def daemonset_pods_for(node)
      node_name =
        node.dig("metadata", "name")

      @pods.select do |pod|
        pod.dig("spec", "nodeName") == node_name &&
          daemonset_pod?(pod)
      end
    end

    def daemonset_pod?(pod)
      owners =
        pod.dig(
          "metadata",
          "ownerReferences"
        ) || []

      owners.any? do |owner|
        owner["kind"] == "DaemonSet"
      end
    end

    # ============================================================
    # Scheduling eligibility
    # ============================================================

    def daemonset_pod_eligible_on_node?(pod, node)
      spec = pod["spec"] || {}

      labels =
        node.dig(
          "metadata",
          "labels"
        ) || {}

      taints =
        node.dig(
          "spec",
          "taints"
        ) || []

      # ----------------------------------------------------------
      # 1. nodeSelector
      # ----------------------------------------------------------

      return false unless
        node_selector_matches?(
          spec["nodeSelector"],
          labels
        )

      # ----------------------------------------------------------
      # 2. nodeAffinity
      # ----------------------------------------------------------

      return false unless
        node_affinity_matches?(
          spec.dig(
            "affinity",
            "nodeAffinity"
          ),
          labels
        )

      # ----------------------------------------------------------
      # 3. taints / tolerations
      # ----------------------------------------------------------

      return false unless
        tolerates_taints?(
          taints,
          spec["tolerations"]
        )

      # ----------------------------------------------------------
      # 4. topologySpreadConstraints
      # ----------------------------------------------------------

      return false unless
        topology_eligible?(
          pod,
          node
        )

      true
    end

    # ============================================================
    # nodeSelector
    # ============================================================

    def node_selector_matches?(selector, labels)
      return true if selector.nil? || selector.empty?

      selector.all? do |key, expected_value|
        labels[key] == expected_value
      end
    end

    # ============================================================
    # nodeAffinity
    # ============================================================

    def node_affinity_matches?(affinity, labels)
      return true if affinity.nil? || affinity.empty?

      required =
        affinity["requiredDuringSchedulingIgnoredDuringExecution"]

      if required
        return false unless
          node_selector_terms_match?(
            required["nodeSelectorTerms"],
            labels
          )
      end

      preferred =
        affinity["preferredDuringSchedulingIgnoredDuringExecution"]

      # preferred は「必須条件」ではないので、
      # 候補Node除外には使わない。
      #
      # Kubernetes schedulerではweightを考慮して優先順位付けされるが、
      # NodeProfileでは「載る可能性」があるかを判定するため、
      # preferredはsoft constraintとして扱う。

      true
    end

    def node_selector_terms_match?(terms, labels)
      return true if terms.nil? || terms.empty?

      terms.any? do |term|
        match_expressions =
          term["matchExpressions"] || []

        match_fields =
          term["matchFields"] || []

        expressions_match?(
          match_expressions,
          labels
        ) &&
          fields_match?(
            match_fields,
            labels
          )
      end
    end

    # ============================================================
    # Node affinity expressions
    # ============================================================

    def expressions_match?(expressions, labels)
      expressions.all? do |expression|
        key = expression["key"]
        operator = expression["operator"]
        values = expression["values"] || []

        actual = labels[key]

        case operator
        when "In"
          values.include?(actual)

        when "NotIn"
          !values.include?(actual)

        when "Exists"
          labels.key?(key)

        when "DoesNotExist"
          !labels.key?(key)

        when "Gt"
          numeric_compare(
            actual,
            values.first
          ) > 0

        when "Lt"
          numeric_compare(
            actual,
            values.first
          ) < 0

        else
          false
        end
      end
    end

    def fields_match?(fields, labels)
      fields.all? do |field|
        # 通常のNode affinityでは metadata.name 等が
        # matchFields に使用される。
        #
        # NodeProfileではNode object全体を渡していないため、
        # labelsに存在するfieldについてのみ評価する。
        key = field["key"]
        operator = field["operator"]
        values = field["values"] || []

        actual = labels[key]

        case operator
        when "In"
          values.include?(actual)

        when "NotIn"
          !values.include?(actual)

        when "Exists"
          labels.key?(key)

        when "DoesNotExist"
          !labels.key?(key)

        else
          false
        end
      end
    end

    def numeric_compare(actual, expected)
      Float(actual) <=> Float(expected)
    rescue ArgumentError, TypeError
      0
    end

    # ============================================================
    # Taints / Tolerations
    # ============================================================

    def tolerates_taints?(taints, tolerations)
      return true if taints.nil? || taints.empty?

      tolerations ||= []

      taints
        .select do |taint|
          effect = taint["effect"]

          # NoSchedule / NoExecute が scheduling に影響
          effect == "NoSchedule" ||
            effect == "NoExecute"
        end
        .all? do |taint|

          toleration_matches_taint?(
            tolerations,
            taint
          )
        end
    end

    def toleration_matches_taint?(tolerations, taint)
      tolerations.any? do |toleration|
        toleration_matches?(
          toleration,
          taint
        )
      end
    end

    def toleration_matches?(toleration, taint)
      taint_key = taint["key"]
      taint_value = taint["value"]
      taint_effect = taint["effect"]

      toleration_key =
        toleration["key"]

      toleration_operator =
        toleration.fetch(
          "operator",
          "Equal"
        )

      toleration_effect =
        toleration["effect"]

      # effect未指定のTolerationは
      # 全effectにmatchする
      if toleration_effect &&
         toleration_effect != taint_effect
        return false
      end

      case toleration_operator
      when "Exists"
        return true if
          toleration_key.nil? ||
          toleration_key == taint_key

      when "Equal"
        return false unless
          toleration_key == taint_key

        return true if
          toleration["value"] == taint_value
      end

      false
    end

    # ============================================================
    # topologySpreadConstraints
    # ============================================================

    def topology_eligible?(pod, node)
      constraints =
        pod.dig(
          "spec",
          "topologySpreadConstraints"
        ) || []

      return true if constraints.empty?

      constraints.all? do |constraint|
        topology_constraint_eligible?(
          pod,
          node,
          constraint
        )
      end
    end

    def topology_constraint_eligible?(
      pod,
      node,
      constraint
    )
      topology_key =
        constraint["topologyKey"]

      return true if topology_key.nil?

      node_labels =
        node.dig(
          "metadata",
          "labels"
        ) || {}

      # topologyKeyを持たないNodeには
      # topology domainが存在しない。
      return false unless
        node_labels.key?(topology_key)

      # nodeAffinityPolicy / nodeTaintsPolicy
      # の扱いも考慮する。
      #
      # 今回はNodeProfileの候補Node判定なので、
      # topology domainが取得できれば候補として扱う。
      #
      # 実際のmaxSkew / whenUnsatisfiableの判定は
      # Cluster全体のPod配置状況が必要になるため、
      #ここでは「topology domainとして有効か」を判定する。

      true
    end

    # ============================================================
    # DaemonSet resource calculation
    # ============================================================

    def daemonset_resources(pods)
      pods.reduce(
        cpu: 0.0,
        memory: 0,
        pods: 0
      ) do |total, pod|

        resources =
          PodResources.calculate(pod)

        {
          cpu:
            total[:cpu] +
            resources[:cpu],

          memory:
            total[:memory] +
            resources[:memory],

          pods:
            total[:pods] + 1
        }
      end
    end

    # ============================================================
    # Node state
    # ============================================================

    def ready?(node)
      conditions =
        node.dig(
          "status",
          "conditions"
        ) || []

      ready =
        conditions.find do |condition|
          condition["type"] == "Ready"
        end

      ready &&
        ready["status"] == "True"
    end

    def unschedulable?(node)
      node.dig(
        "spec",
        "unschedulable"
      ) == true
    end

    # ============================================================
    # Statistics
    # ============================================================

    def statistics(values)
      values =
        values.compact.sort

      {
        min: values.first,
        max: values.last,
        median: percentile(values, 50),
        p25: percentile(values, 25),
        p75: percentile(values, 75),
        value: percentile(
          values,
          @percentile
        )
      }
    end

    def percentile(values, percentile)
      return 0 if values.empty?
      return values.first if values.size == 1

      rank =
        (percentile / 100.0) *
        (values.length - 1)

      lower =
        values[rank.floor]

      upper =
        values[rank.ceil]

      lower +
        (
          (upper - lower) *
          (rank - rank.floor)
        )
    end

    class InsufficientData < StandardError
    end
  end
end
```

### 重要な修正点

今回の実装では、DaemonSet Podについて、

```text
現在Nodeに載っているDaemonSet
        ↓
nodeSelector
        ↓
required nodeAffinity
        ↓
taints / tolerations
        ↓
topologyKey
        ↓
将来Nodeにも載る可能性があるか
        ↓
DaemonSetのCPU / Memory / Pod slotを控除
```

という流れになります。

例えば、

```yaml
spec:
  nodeSelector:
    workload: general

  tolerations:
    - key: dedicated
      operator: Equal
      value: general
      effect: NoSchedule

  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
          - matchExpressions:
              - key: kubernetes.io/arch
                operator: In
                values:
                  - amd64
```

というDaemonSetなら、候補Nodeが

```text
workload=general
kubernetes.io/arch=amd64
```

を持ち、さらに必要なtaintをtolerateできる場合だけ、そのDaemonSetのリソースをNodeProfileから差し引きます。

---

## ただし `topologySpreadConstraints` はもう一段改善した方がいい

ここは今回の実装で最も注意が必要です。

例えば、

```yaml
topologySpreadConstraints:
  - maxSkew: 1
    topologyKey: topology.kubernetes.io/zone
    whenUnsatisfiable: DoNotSchedule
    labelSelector:
      matchLabels:
        app: my-app
```

の場合、

```text
zone=a
zone=b
zone=c
```

の現在のPod数を見ないと、

> 新しいNodeをzone=bに追加したらこのPodを配置できるか

を正確には判断できません。

したがって、今回の `topology_eligible?` は意図的に、

> **そのNodeが有効なtopology domainを持っているか**

までに留めています。

完全に実用的なEstimatorにするなら、次の段階として `TopologyAnalyzer` を追加するのがおすすめです。

```ruby
TopologyAnalyzer
  .new(
    nodes: nodes,
    pods: pods
  )
  .eligible?(
    pod: daemonset_pod,
    node: candidate_node
  )
```

ここで、

* `topologyKey`
* `maxSkew`
* `whenUnsatisfiable`
* `labelSelector`
* `matchLabelKeys`
* `nodeAffinityPolicy`
* `nodeTaintsPolicy`
* 各topology domainのPod数

まで評価します。

特に今回の目的が **「あと何Pod起動できるか」** なのであれば、Topologyについては `NodeProfileEstimator` に直接ロジックを増やすより、

```text
NodeProfileEstimator
       │
       ├── NodeSelectorMatcher
       ├── NodeAffinityMatcher
       ├── TaintTolerationMatcher
       └── TopologyAnalyzer
```

と分離した方が後々かなり扱いやすいです。

また、Karpenterの場合はさらに重要で、**「現在存在するNode」だけを候補にするのではなく、NodePoolのrequirementsから「これからKarpenterが作れるNode」の制約を候補Nodeに反映する**のが理想です。

つまり最終形は、

```text
Karpenter NodePool
        │
        │ requirements
        ▼
Candidate Node Profile
        │
        ├─ CPU / Memory / maxPods
        ├─ labels
        ├─ taints
        ├─ zone
        ├─ instance type
        └─ architecture
                │
                ▼
       DaemonSet scheduling
                │
       ┌────────┼────────┐
       ▼        ▼        ▼
 nodeSelector affinity  topology
       │        │        │
       └────────┼────────┘
                ▼
       DaemonSet overhead
                │
                ▼
       usable Node capacity
```

となります。

**実際のEstimatorとしてはこの形がかなり良いです。**
特に `topologySpreadConstraints` まで含めるなら、次は `TopologyAnalyzer` と `Karpenter NodePool requirements → CandidateNode` を追加すると、かなり実用的な「追加Pod数推定器」になります。

