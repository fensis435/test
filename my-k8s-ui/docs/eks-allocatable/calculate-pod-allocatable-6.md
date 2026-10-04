前回の `NodeProfileEstimator` を一段進めて、以下の構成にするのがよいです。

```text
Karpenter NodePool
       │
       ├─ template.metadata.labels
       ├─ template.spec.taints
       └─ template.spec.requirements
                │
                ▼
      CandidateNodeBuilder
                │
                ▼
       Candidate Nodes
                │
       ┌────────┼──────────┐
       ▼        ▼          ▼
 nodeSelector affinity  taints
       │        │          │
       └────────┼──────────┘
                ▼
        TopologyAnalyzer
                │
        maxSkew / domain
        existing Pod count
                │
                ▼
       DaemonSet overhead
                │
                ▼
        NodeProfileEstimator
```

KarpenterのNodePool `requirements` は、Pod側の `nodeSelector` / `nodeAffinity` 等と組み合わされてNodeClaimの制約になります。またNodePoolのlabelsもNodeClaimのrequirementsとして扱われます。([Karpenter][1])

`topologySpreadConstraints` は `maxSkew`、`labelSelector`、`nodeAffinityPolicy`、`nodeTaintsPolicy` などを使って既存Podのdomain別分布を評価する必要があります。([Kubernetes][2])

以下は、その前提でまとめた実装です。

---

# 1. `KarpenterCandidateNodeBuilder`

まずNodePoolから「Karpenterが作り得るNode」を表す候補を作ります。

ここで重要なのは、Karpenterのrequirementsが

```yaml
- key: topology.kubernetes.io/zone
  operator: In
  values:
    - ap-northeast-1a
    - ap-northeast-1c
```

のように有限値を持つ場合は、その値を候補として利用できることです。

一方、

```yaml
- key: node.kubernetes.io/instance-type
  operator: Exists
```

のようなものは具体的なNodeスペックを確定できません。

そのため、**現在実際に存在するNodeを「実測Node profile」として使い、そのNodeがNodePool requirementsを満たすものだけを将来Nodeのprofile候補として利用する**方式にします。

```ruby
module ClusterCapacity
  class KarpenterCandidateNodeBuilder
    def initialize(nodes:, nodepool:)
      @nodes = nodes
      @nodepool = nodepool
    end

    def candidates
      @nodes.select do |node|
        node_matches_nodepool?(node)
      end
    end

    private

    def node_matches_nodepool?(node)
      labels = effective_labels(node)
      requirements.all? do |requirement|
        requirement_matches?(requirement, labels)
      end
    end

    def effective_labels(node)
      node_labels =
        node.dig("metadata", "labels") || {}

      template_labels =
        @nodepool.dig(
          "spec",
          "template",
          "metadata",
          "labels"
        ) || {}

      # 実Nodeのlabelを基本にする。
      # NodePool labelは必須条件として上書き。
      node_labels.merge(template_labels)
    end

    def requirements
      @nodepool.dig(
        "spec",
        "template",
        "spec",
        "requirements"
      ) || []
    end

    def requirement_matches?(requirement, labels)
      key = requirement["key"]
      operator = requirement["operator"]
      values = requirement["values"] || []

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
        compare(actual, values.first) > 0

      when "Lt"
        compare(actual, values.first) < 0

      when "Gte"
        compare(actual, values.first) >= 0

      when "Lte"
        compare(actual, values.first) <= 0

      else
        false
      end
    end

    def compare(actual, expected)
      Float(actual) <=> Float(expected)
    rescue ArgumentError, TypeError
      0
    end
  end
end
```

### NodePoolのtaintも候補Nodeに付与する

Karpenter NodePoolの `template.spec.taints` は、実際にProvisionされたNodeに付与されます。Podがそのtaintをtolerateできなければ、そのNodePoolはそのPodには使えません。([Karpenter][1])

そこで候補NodeにNodePool taintをマージします。

```ruby
module ClusterCapacity
  class KarpenterCandidateNodeBuilder
    # ...

    def candidates
      @nodes
        .select { |node| node_matches_nodepool?(node) }
        .map { |node| apply_nodepool_template(node) }
    end

    private

    def apply_nodepool_template(node)
      copy = Marshal.load(Marshal.dump(node))

      labels =
        copy.dig(
          "metadata",
          "labels"
        ) || {}

      nodepool_labels =
        @nodepool.dig(
          "spec",
          "template",
          "metadata",
          "labels"
        ) || {}

      copy["metadata"]["labels"] =
        labels.merge(nodepool_labels)

      nodepool_taints =
        @nodepool.dig(
          "spec",
          "template",
          "spec",
          "taints"
        ) || []

      existing_taints =
        copy.dig(
          "spec",
          "taints"
        ) || []

      copy["spec"]["taints"] =
        merge_taints(
          existing_taints,
          nodepool_taints
        )

      copy
    end

    def merge_taints(existing, additional)
      result = existing.map(&:dup)

      additional.each do |taint|
        result.reject! do |existing_taint|
          existing_taint["key"] == taint["key"] &&
            existing_taint["effect"] == taint["effect"]
        end

        result << taint
      end

      result
    end

    # ...
  end
end
```

これによって、

```text
実Node
  +
NodePool labels
  +
NodePool taints
  +
NodePool requirements
```

を反映したCandidate Nodeになります。

---

# 2. `TopologyAnalyzer`

次にTopologyです。

ここは単純な

```ruby
topology_key が存在する
```

だけでは不十分です。

例えば、

```yaml
topologySpreadConstraints:
  - maxSkew: 1
    topologyKey: topology.kubernetes.io/zone
    whenUnsatisfiable: DoNotSchedule
    labelSelector:
      matchLabels:
        app: web
```

なら、

```text
zone-a: 5 Pods
zone-b: 5 Pods
zone-c: 2 Pods
```

という状態でzone-cに追加するのはOKですが、zone-aに追加すると

```text
zone-a: 6
zone-b: 5
zone-c: 2
```

となり、skewが4になるため `DoNotSchedule` ならNGです。

KubernetesのTopology Spreadは、既存のselectorにマッチするPodをdomainごとに数えてskewを計算します。([Kubernetes][2])

そこで専用クラスにします。

```ruby
module ClusterCapacity
  class TopologyAnalyzer
    def initialize(nodes:, pods:)
      @nodes = nodes
      @pods = pods
    end

    def eligible?(pod:, candidate_node:)
      constraints =
        pod.dig(
          "spec",
          "topologySpreadConstraints"
        ) || []

      constraints.all? do |constraint|
        constraint_eligible?(
          pod,
          candidate_node,
          constraint
        )
      end
    end

    private

    def constraint_eligible?(
      pod,
      candidate_node,
      constraint
    )
      topology_key =
        constraint["topologyKey"]

      return true unless topology_key

      candidate_labels =
        node_labels(candidate_node)

      candidate_domain =
        candidate_labels[topology_key]

      # topologyKeyを持たないNodeは対象外
      return false if candidate_domain.nil?

      matching_pods =
        matching_pods_for(
          pod,
          constraint
        )

      domains =
        eligible_domains(
          pod,
          constraint
        )

      counts =
        domain_counts(
          matching_pods,
          topology_key,
          domains
        )

      # Candidate Nodeを仮想的に1 Pod増やす
      counts[candidate_domain] =
        counts.fetch(candidate_domain, 0) + 1

      min_count =
        minimum_domain_count(
          counts,
          domains,
          constraint
        )

      max_count =
        counts.values.max || 0

      max_skew =
        constraint.fetch(
          "maxSkew",
          1
        ).to_i

      skew =
        max_count - min_count

      if constraint.fetch(
        "whenUnsatisfiable",
        "DoNotSchedule"
      ) == "DoNotSchedule"

        skew <= max_skew
      else
        # ScheduleAnywayの場合は
        # hard constraintではない。
        true
      end
    end

    # ----------------------------------------------------------
    # Matching Pods
    # ----------------------------------------------------------

    def matching_pods_for(pod, constraint)
      selector =
        build_label_selector(
          pod,
          constraint
        )

      @pods.select do |existing_pod|
        label_selector_matches?(
          selector,
          existing_pod.dig(
            "metadata",
            "labels"
          ) || {}
        )
      end
    end

    def build_label_selector(pod, constraint)
      selector =
        deep_dup(
          constraint["labelSelector"] || {}
        )

      match_label_keys =
        constraint["matchLabelKeys"] || []

      selector["matchLabels"] ||= {}

      labels =
        pod.dig(
          "metadata",
          "labels"
        ) || {}

      match_label_keys.each do |key|
        next unless labels.key?(key)

        selector["matchLabels"][key] =
          labels[key]
      end

      selector
    end

    # ----------------------------------------------------------
    # Domain
    # ----------------------------------------------------------

    def eligible_domains(pod, constraint)
      topology_key =
        constraint["topologyKey"]

      policy =
        constraint.fetch(
          "nodeAffinityPolicy",
          "Honor"
        )

      taints_policy =
        constraint.fetch(
          "nodeTaintsPolicy",
          "Ignore"
        )

      @nodes
        .select do |node|
          topology_node_eligible?(
            pod,
            node,
            policy,
            taints_policy
          )
        end
        .map do |node|
          node_labels(node)[topology_key]
        end
        .compact
        .uniq
    end

    def topology_node_eligible?(
      pod,
      node,
      affinity_policy,
      taints_policy
    )
      if affinity_policy == "Honor"
        return false unless
          node_affinity_matches?(
            pod,
            node
          )
      end

      if taints_policy == "Honor"
        return false unless
          tolerates_taints?(
            pod,
            node
          )
      end

      true
    end

    # ----------------------------------------------------------
    # Counts
    # ----------------------------------------------------------

    def domain_counts(
      pods,
      topology_key,
      domains
    )
      counts =
        domains.each_with_object({}) do |domain, result|
          result[domain] = 0
        end

      pods.each do |pod|
        node_name =
          pod.dig(
            "spec",
            "nodeName"
          )

        next unless node_name

        node =
          @nodes.find do |candidate|
            candidate.dig(
              "metadata",
              "name"
            ) == node_name
          end

        next unless node

        domain =
          node_labels(node)[topology_key]

        next unless domain

        counts[domain] =
          counts.fetch(domain, 0) + 1
      end

      counts
    end

    def minimum_domain_count(
      counts,
      domains,
      constraint
    )
      return 0 if domains.empty?

      # minDomainsが指定されている場合、
      # eligible domain数がminDomains未満なら
      # KubernetesのminDomains semanticsを考慮する。
      min_domains =
        constraint["minDomains"]

      if min_domains &&
         domains.size < min_domains.to_i

        return 0
      end

      counts.values.min || 0
    end

    # ----------------------------------------------------------
    # Label selector
    # ----------------------------------------------------------

    def label_selector_matches?(selector, labels)
      match_labels =
        selector["matchLabels"] || {}

      return false unless
        match_labels.all? do |key, value|
          labels[key] == value
        end

      match_expressions =
        selector["matchExpressions"] || []

      match_expressions.all? do |expression|
        selector_expression_matches?(
          expression,
          labels
        )
      end
    end

    def selector_expression_matches?(expression, labels)
      key =
        expression["key"]

      operator =
        expression["operator"]

      values =
        expression["values"] || []

      actual =
        labels[key]

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

    # ----------------------------------------------------------
    # Node scheduling predicates
    # ----------------------------------------------------------

    def node_affinity_matches?(pod, node)
      labels =
        node_labels(node)

      selector =
        pod.dig(
          "spec",
          "nodeSelector"
        ) || {}

      return false unless
        selector.all? do |key, value|
          labels[key] == value
        end

      affinity =
        pod.dig(
          "spec",
          "affinity",
          "nodeAffinity",
          "requiredDuringSchedulingIgnoredDuringExecution"
        )

      return true unless affinity

      terms =
        affinity["nodeSelectorTerms"] || []

      terms.any? do |term|
        expressions =
          term["matchExpressions"] || []

        expressions.all? do |expression|
          selector_expression_matches?(
            expression,
            labels
          )
        end
      end
    end

    def tolerates_taints?(pod, node)
      taints =
        node.dig(
          "spec",
          "taints"
        ) || []

      tolerations =
        pod.dig(
          "spec",
          "tolerations"
        ) || []

      taints
        .select do |taint|
          %w[NoSchedule NoExecute].include?(
            taint["effect"]
          )
        end
        .all? do |taint|

          tolerations.any? do |toleration|
            toleration_matches?(
              toleration,
              taint
            )
          end
        end
    end

    def toleration_matches?(toleration, taint)
      effect =
        toleration["effect"]

      return false if
        effect &&
        effect != taint["effect"]

      key =
        toleration["key"]

      operator =
        toleration.fetch(
          "operator",
          "Equal"
        )

      if operator == "Exists"
        return true if
          key.nil? ||
          key == taint["key"]
      end

      operator == "Equal" &&
        key == taint["key"] &&
        toleration["value"] == taint["value"]
    end

    def node_labels(node)
      node.dig(
        "metadata",
        "labels"
      ) || {}
    end

    def deep_dup(object)
      Marshal.load(
        Marshal.dump(object)
      )
    end
  end
end
```

---

# 3. `NodeProfileEstimator` を統合

これで `NodeProfileEstimator` は、単なるDaemonSetリソース集計ではなくなります。

```ruby
module ClusterCapacity
  class NodeProfileEstimator
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

      @topology_analyzer =
        TopologyAnalyzer.new(
          nodes: nodes,
          pods: pods
        )
    end

    def estimate
      candidates =
        candidate_nodes

      raise InsufficientData,
            "Not enough candidate nodes" if
              candidates.size < @min_nodes

      profiles =
        candidates.map do |node|

          build_profile(node)
        end

      {
        node_count: profiles.size,

        cpu: statistics(
          profiles.map { |p| p[:cpu] }
        ),

        memory: statistics(
          profiles.map { |p| p[:memory] }
        ),

        pods: statistics(
          profiles.map { |p| p[:pods] }
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

    # ==========================================================
    # Candidate Nodes
    # ==========================================================

    def candidate_nodes
      nodes =
        if @nodepool
          KarpenterCandidateNodeBuilder
            .new(
              nodes: @nodes,
              nodepool: @nodepool
            )
            .candidates
        else
          @nodes
        end

      nodes.select do |node|
        ready?(node) &&
          !unschedulable?(node) &&
          nodepool_name_match?(node)
      end
    end

    def nodepool_name_match?(node)
      return true unless @nodepool_name

      node.dig(
        "metadata",
        "labels",
        "karpenter.sh/nodepool"
      ) == @nodepool_name
    end

    # ==========================================================
    # Profile
    # ==========================================================

    def build_profile(node)
      allocatable =
        node.dig(
          "status",
          "allocatable"
        ) || {}

      alloc_cpu =
        Quantity.cpu(
          allocatable["cpu"]
        )

      alloc_memory =
        Quantity.memory(
          allocatable["memory"]
        )

      alloc_pods =
        allocatable
          .fetch("pods", "0")
          .to_i

      daemonset_pods =
        daemonset_pods_for(node)

      eligible_daemonsets =
        daemonset_pods.select do |pod|
          daemonset_eligible?(
            pod,
            node
          )
        end

      resources =
        daemonset_resources(
          eligible_daemonsets
        )

      effective_cpu =
        [
          alloc_cpu - resources[:cpu],
          0
        ].max

      effective_memory =
        [
          alloc_memory - resources[:memory],
          0
        ].max

      effective_pods =
        [
          alloc_pods - resources[:pods],
          0
        ].max

      {
        node:
          node.dig(
            "metadata",
            "name"
          ),

        allocatable: {
          cpu: alloc_cpu,
          memory: alloc_memory,
          pods: alloc_pods
        },

        daemonset: resources,

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

    # ==========================================================
    # DaemonSet
    # ==========================================================

    def daemonset_pods_for(node)
      node_name =
        node.dig(
          "metadata",
          "name"
        )

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

    def daemonset_eligible?(pod, node)
      spec =
        pod["spec"] || {}

      # nodeSelector
      labels =
        node.dig(
          "metadata",
          "labels"
        ) || {}

      selector =
        spec["nodeSelector"] || {}

      return false unless
        selector.all? do |key, value|
          labels[key] == value
        end

      # required nodeAffinity
      affinity =
        spec.dig(
          "affinity",
          "nodeAffinity",
          "requiredDuringSchedulingIgnoredDuringExecution"
        )

      if affinity
        terms =
          affinity["nodeSelectorTerms"] || []

        return false unless
          terms.any? do |term|
            affinity_term_matches?(
              term,
              labels
            )
          end
      end

      # taints
      return false unless
        tolerates_taints?(
          pod,
          node
        )

      # topology
      return false unless
        @topology_analyzer.eligible?(
          pod: pod,
          candidate_node: node
        )

      true
    end

    def affinity_term_matches?(term, labels)
      expressions =
        term["matchExpressions"] || []

      expressions.all? do |expression|
        key =
          expression["key"]

        operator =
          expression["operator"]

        values =
          expression["values"] || []

        actual =
          labels[key]

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
          Float(actual) > Float(values.first)

        when "Lt"
          Float(actual) < Float(values.first)

        when "Gte"
          Float(actual) >= Float(values.first)

        when "Lte"
          Float(actual) <= Float(values.first)

        else
          false
        end
      end
    rescue ArgumentError, TypeError
      false
    end

    # ==========================================================
    # Taints
    # ==========================================================

    def tolerates_taints?(pod, node)
      taints =
        node.dig(
          "spec",
          "taints"
        ) || []

      tolerations =
        pod.dig(
          "spec",
          "tolerations"
        ) || []

      taints
        .select do |taint|
          %w[NoSchedule NoExecute].include?(
            taint["effect"]
          )
        end
        .all? do |taint|

          tolerations.any? do |toleration|
            toleration_matches?(
              toleration,
              taint
            )
          end
        end
    end

    def toleration_matches?(toleration, taint)
      effect =
        toleration["effect"]

      return false if
        effect &&
        effect != taint["effect"]

      operator =
        toleration.fetch(
          "operator",
          "Equal"
        )

      key =
        toleration["key"]

      case operator
      when "Exists"
        key.nil? || key == taint["key"]

      when "Equal"
        key == taint["key"] &&
          toleration["value"] == taint["value"]

      else
        false
      end
    end

    # ==========================================================
    # Resources
    # ==========================================================

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

    # ==========================================================
    # Node state
    # ==========================================================

    def ready?(node)
      conditions =
        node.dig(
          "status",
          "conditions"
        ) || []

      condition =
        conditions.find do |item|
          item["type"] == "Ready"
        end

      condition &&
        condition["status"] == "True"
    end

    def unschedulable?(node)
      node.dig(
        "spec",
        "unschedulable"
      ) == true
    end

    # ==========================================================
    # Statistics
    # ==========================================================

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
        percentile / 100.0 *
        (values.length - 1)

      lower =
        values[rank.floor]

      upper =
        values[rank.ceil]

      lower +
        (upper - lower) *
        (rank - rank.floor)
    end

    class InsufficientData < StandardError
    end
  end
end
```

## 4. NodePoolをAPIから取得する

今までの `KarpenterCapacity` にNodePool取得を追加します。

```ruby
module ClusterCapacity
  class KarpenterClient
    def initialize(kubernetes_client:)
      @client = kubernetes_client
    end

    def nodepool(name)
      @client.get(
        "/apis/karpenter.sh/v1/nodepools/#{name}"
      )
    end
  end
end
```

そして、

```ruby
nodepool =
  karpenter_client.nodepool(
    "default"
  )

profile =
  ClusterCapacity::NodeProfileEstimator.new(
    nodes: nodes,
    pods: pods,
    nodepool_name: "default",
    nodepool: nodepool,
    percentile: 25,
    min_nodes: 2
  ).profile
```

とします。

---

# 5. この設計で何が改善されるか

例えばNodePoolが、

```yaml
spec:
  template:
    metadata:
      labels:
        workload: general

    spec:
      taints:
        - key: dedicated
          value: general
          effect: NoSchedule

      requirements:
        - key: kubernetes.io/arch
          operator: In
          values:
            - amd64

        - key: topology.kubernetes.io/zone
          operator: In
          values:
            - ap-northeast-1a
            - ap-northeast-1c
```

だったとします。

するとEstimatorは、

```text
現在のNode
       │
       ├─ NodePool requirementsを満たす？
       │
       ├─ workload=general？
       │
       ├─ amd64？
       │
       ├─ zone=a/c？
       │
       └─ NodePool taintを反映
              │
              ▼
       Candidate Node
              │
              ├─ DaemonSet nodeSelector
              ├─ DaemonSet nodeAffinity
              ├─ DaemonSet tolerations
              └─ topologySpreadConstraints
                       │
                       ▼
                DaemonSet overhead
                       │
                       ▼
             Future Node capacity
```

という評価になります。

---

## `topologySpreadConstraints` の評価例

例えば、

```text
zone-a: 5 Pods
zone-b: 5 Pods
zone-c: 2 Pods
```

で、

```yaml
maxSkew: 1
topologyKey: topology.kubernetes.io/zone
whenUnsatisfiable: DoNotSchedule
```

なら、

```text
candidate zone-a
    ↓
6 / 5 / 2
    ↓
skew = 4
    ↓
NG

candidate zone-c
    ↓
5 / 5 / 3
    ↓
skew = 2
    ↓
NG
```

となります。

この例では新しいPodをどこに置いても `maxSkew=1` を維持できないので、そのPodについては候補から外します。

実際のKubernetes schedulerでも、`DoNotSchedule` はhard constraint、`ScheduleAnyway` はsoft constraintとして扱われます。([Kubernetes][2])

---

# 6. ただし、ここには一つ重要な限界があります

この実装では、

> **「未来のNodeのCPU/Memory capacity」については、既存Nodeの実測値を使う**

という設計です。

例えばKarpenterが、

```yaml
requirements:
  - key: node.kubernetes.io/instance-type
    operator: In
    values:
      - m6i.large
      - m6i.xlarge
      - m6i.2xlarge
```

を持っている場合、

```text
m6i.large
m6i.xlarge
m6i.2xlarge
```

ではCPU/Memoryが違います。

NodePool requirementsだけでは、

> 次にどのinstance typeが選ばれるか

は確定できません。Karpenter自体もNodePoolのrequirementsとPod側のrequirementsを組み合わせてNodeClaim候補を決定します。([Karpenter][1])

なので、このEstimatorでは、

```text
NodePool requirements
        ↓
既存Nodeから条件に合うNodeだけ抽出
        ↓
そのNodeの実測 allocatable
        ↓
p25
        ↓
future Node profile
```

としています。

これは今回の「厳密値ではなく実用的な指標」という目的にはかなり合っています。

---

# 7. 最終的な責務分割

ここまで実装すると、かなり綺麗に分離できます。

```text
ClusterCapacity
│
├── Quantity
│
├── PodResources
│
├── KubernetesCapacity
│
├── KarpenterClient
│
├── KarpenterCapacity
│
├── KarpenterCandidateNodeBuilder
│
├── TopologyAnalyzer
│
├── NodeProfileEstimator
│
├── AwsCapacity
│
└── Estimator
```

特に重要なのは、

```text
KarpenterCandidateNodeBuilder
```

と

```text
TopologyAnalyzer
```

を `NodeProfileEstimator` から分離したことです。

これによってオンプレKubernetesの場合は、

```ruby
NodeProfileEstimator.new(
  nodes: nodes,
  pods: pods
)
```

だけでも使えます。

Karpenterの場合だけ、

```ruby
NodeProfileEstimator.new(
  nodes: nodes,
  pods: pods,
  nodepool_name: "default",
  nodepool: nodepool
)
```

としてprovider-specificな候補Node制約を追加できます。

---

## さらに一段実用的にするなら

次に追加する価値が高いのは **`CandidateNodeProfile`** です。

今の実装では「既存Nodeを未来Nodeのproxyとして使う」ため、

```text
NodePool requirements
        ↓
候補Node
        ↓
実測 CPU / Memory
```

ですが、AWS EKS + Karpenterなら、

```text
NodePool requirements
        ↓
instance type候補
        ↓
EC2 instance type情報
        ↓
allocatable CPU / Memory / maxPods
        ↓
DaemonSet overhead
        ↓
CandidateNodeProfile
```

まで持っていくとかなり精度が上がります。

さらに、

```text
CandidateNodeProfile
 ├── instance type
 ├── zone
 ├── CPU
 ├── memory
 ├── maxPods
 ├── ENI/IP capacity
 └── daemonset overhead
```

を複数候補について作って、**「最も悲観的な候補」「中央値」「最も楽観的な候補」**を出せるようにすると、AWS vCPU quota / subnet IP / NodePool limits と組み合わせた最終的な `estimated_available_pods` がかなり実用的になります。

特にKarpenterではNodePoolの`requirements`にzoneやinstance type、architecture、capacity typeなどを指定できるため、この方向が次の改善として最も効果的です。([Karpenter][1])

[1]: https://karpenter.sh/docs/concepts/nodepools/?utm_source=chatgpt.com "NodePools | Karpenter"
[2]: https://kubernetes.io/docs/concepts/scheduling-eviction/topology-spread-constraints/?utm_source=chatgpt.com "Pod Topology Spread Constraints | Kubernetes"
