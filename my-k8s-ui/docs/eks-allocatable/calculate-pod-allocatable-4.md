ここまで来たら、`NodeProfileEstimator` は **「Karpenterが今後1台Nodeを増やしたとき、そのNodeから実際に何Podくらいのcapacityが得られるか」** を推定するクラスにするのがよいです。

ポイントは、単に `allocatable / pod_request` としないことです。

* `allocatable` はすでに kube/system reservation を除いている
* さらに既存Node上の **DaemonSet Podのrequests** を除く
* 複数Nodeの実績から **median / p25** を使う
* KarpenterのNodePoolに属するNodeだけを対象にする
* `maxPods` も考慮する
* そのNode profileを使って「追加可能Node数」をPod数に変換する

という方式にします。

以下のような構成を提案します。

---

# 1. 全体構成

前回のクラス群に、

```text
KubernetesCapacity
       │
       ├── 現在の空きcapacity
       │
       ▼
NodeProfileEstimator
       │
       ├── Node 1台あたりの実効CPU
       ├── Node 1台あたりの実効Memory
       ├── Node 1台あたりの実効Pod slots
       │
       ▼
KarpenterCapacity
       │
       ├── NodePool remaining CPU
       ├── NodePool remaining Memory
       ├── AWS quota
       ├── subnet
       │
       ▼
ProjectedCapacity
       │
       ▼
estimated_available_pods
```

とします。

---

# 2. `NodeProfileEstimator`

まずこれを追加します。

```ruby
# frozen_string_literal: true

module ClusterCapacity

  class NodeProfileEstimator

    # ------------------------------------------------------------------------
    # profile:
    #
    # {
    #   cpu: 7800,
    #   memory: 30.gibibytes,
    #   pods: 90
    # }
    #
    # は「このNodeに新しいPodをどれくらい載せられるか」の推定値。
    # ------------------------------------------------------------------------

    def initialize(
      nodes:,
      pods:,
      nodepool_name: nil,
      percentile: 50,
      min_nodes: 2
    )
      @nodes = nodes
      @pods = pods
      @nodepool_name = nodepool_name
      @percentile = percentile
      @min_nodes = min_nodes
    end

    def estimate
      selected_nodes = select_nodes

      raise InsufficientData,
            "Not enough nodes to estimate Node profile" if
        selected_nodes.size < @min_nodes

      profiles =
        selected_nodes.map do |node|
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

    def select_nodes
      @nodes.select do |node|

        next false unless ready?(node)
        next false if unschedulable?(node)

        if @nodepool_name
          nodepool =
            node.dig(
              "metadata",
              "labels",
              "karpenter.sh/nodepool"
            )

          next false unless nodepool == @nodepool_name
        end

        true
      end
    end

    def build_profile(node)
      node_name =
        node.dig("metadata", "name")

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

      node_pods =
        @pods.select do |pod|
          pod.dig("spec", "nodeName") == node_name
        end

      daemonset_pods =
        node_pods.select do |pod|
          daemonset_pod?(pod)
        end

      daemonset_resources =
        daemonset_pods.reduce(
          cpu: 0.0,
          memory: 0
        ) do |total, pod|

          resources =
            PodResources.calculate(pod)

          {
            cpu:
              total[:cpu] + resources[:cpu],

            memory:
              total[:memory] + resources[:memory]
          }
        end

      daemonset_pod_count =
        daemonset_pods.size

      # ----------------------------------------------------------------------
      # 重要:
      #
      # 新しいNodeには既存Workload Podは乗っていない。
      #
      # しかしDaemonSetは新Nodeにも乗るので、
      #
      # allocatable
      # -
      # expected DaemonSet resources
      #
      # を「新しいNodeの実効capacity」とみなす。
      # ----------------------------------------------------------------------

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
          alloc_pods - daemonset_pod_count,
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
          pods: daemonset_pod_count
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

    # ------------------------------------------------------------------------
    # percentile
    #
    # percentile=50 → median
    # percentile=25 → p25
    #
    # p25を使うと保守的なNode profileになる。
    # ------------------------------------------------------------------------

    def statistics(values)
      values =
        values
          .compact
          .sort

      {
        min: values.first,
        max: values.last,
        median: percentile(values, 50),
        p25: percentile(values, 25),
        p75: percentile(values, 75),
        value: percentile(values, @percentile)
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
        ((upper - lower) * (rank - rank.floor))
    end

    class InsufficientData < StandardError
    end
  end
end
```

---

# 3. なぜDaemonSetを引くのか

ここがこのクラスの一番重要なところです。

例えばNodeが、

```text
allocatable

CPU      8
Memory   32Gi
Pods     110
```

だとして、

DaemonSetが、

```text
CPU      200m
Memory   512Mi
Pods     4
```

を使っているとします。

新しいNodeをKarpenterが起動した場合、当然DaemonSetもそこに起動するので、

```text
新Nodeの実効capacity

CPU
  8 - 0.2
  = 7.8

Memory
  32 - 0.5
  = 31.5Gi

Pods
  110 - 4
  = 106
```

となります。

したがって、

```text
Pod request = 500m / 1Gi
```

なら、

```text
CPU      15 Pod
Memory   31 Pod
Pod slot 106 Pod
```

なので、

**このNodeは約15 Podのcapacity**

と判断します。

これは単純な

```text
8 / 0.5 = 16
```

より現実的です。

---

# 4. medianではなくp25を使えるようにする

Nodeの種類が複数あるKarpenter環境では、

```text
Node A   8 CPU
Node B   8 CPU
Node C   8 CPU
Node D   16 CPU
Node E   16 CPU
```

のようになることがあります。

このとき平均値を使うと、将来Karpenterがどちらを選ぶか分からないので微妙です。

そこで、

```ruby
percentile: 50
```

ならmedian。

```ruby
percentile: 25
```

ならp25。

とします。

安全側に倒すなら、

```ruby
NodeProfileEstimator.new(
  nodes: nodes,
  pods: pods,
  nodepool_name: "default",
  percentile: 25
)
```

がおすすめです。

---

# 5. Karpenter CapacityにNodeProfileを統合する

次に、前回の `KarpenterCapacity` を少し拡張します。

```ruby
# frozen_string_literal: true

module ClusterCapacity

  class KarpenterCapacity

    def initialize(
      client:,
      nodepool_name:,
      nodes:,
      pods:
    )
      @client = client
      @nodepool_name = nodepool_name
      @nodes = nodes
      @pods = pods
    end

    def calculate
      nodepool =
        @client.get(
          "/apis/karpenter.sh/v1/nodepools/#{@nodepool_name}"
        )

      spec_limits =
        nodepool.dig(
          "spec",
          "limits"
        ) || {}

      status_resources =
        nodepool.dig(
          "status",
          "resources"
        ) || {}

      result = {}

      # ----------------------------------------------------------------------
      # CPU
      # ----------------------------------------------------------------------

      if spec_limits["cpu"]

        limit =
          Quantity.cpu(
            spec_limits["cpu"]
          )

        used =
          Quantity.cpu(
            status_resources["cpu"]
          )

        result[:cpu] = {
          limit: limit,
          used: used,
          remaining: [
            limit - used,
            0
          ].max
        }
      end

      # ----------------------------------------------------------------------
      # Memory
      # ----------------------------------------------------------------------

      if spec_limits["memory"]

        limit =
          Quantity.memory(
            spec_limits["memory"]
          )

        used =
          Quantity.memory(
            status_resources["memory"]
          )

        result[:memory] = {
          limit: limit,
          used: used,
          remaining: [
            limit - used,
            0
          ].max
        }
      end

      # ----------------------------------------------------------------------
      # Node limit
      # ----------------------------------------------------------------------

      if spec_limits["nodes"]

        limit =
          spec_limits["nodes"].to_i

        used =
          nodepool.dig(
            "status",
            "nodes"
          ).to_i

        result[:nodes] = {
          limit: limit,
          used: used,
          remaining: [
            limit - used,
            0
          ].max
        }
      end

      # ----------------------------------------------------------------------
      # Node profile
      # ----------------------------------------------------------------------

      profile =
        NodeProfileEstimator.new(
          nodes: @nodes,
          pods: @pods,
          nodepool_name: @nodepool_name,
          percentile: 25,
          min_nodes: 2
        )

      result[:profile] =
        profile.estimate

      # ----------------------------------------------------------------------
      # Estimated additional nodes
      # ----------------------------------------------------------------------

      result[:additional_nodes] =
        estimate_additional_nodes(
          result
        )

      result
    end

    private

    def estimate_additional_nodes(result)
      candidates = []

      profile =
        result.dig(
          :profile,
          :cpu,
          :value
        )

      if profile && profile > 0 && result[:cpu]
        candidates << (
          result[:cpu][:remaining] / profile
        ).floor
      end

      memory_profile =
        result.dig(
          :profile,
          :memory,
          :value
        )

      if memory_profile &&
         memory_profile > 0 &&
         result[:memory]

        candidates << (
          result[:memory][:remaining] /
          memory_profile
        ).floor
      end

      if result[:nodes]
        candidates << result[:nodes][:remaining]
      end

      return 0 if candidates.empty?

      candidates.min
    end
  end
end
```

---

# 6. ここで「Karpenterがあと何Node作れるか」が分かる

例えば、

```text
NodePool:

limit CPU = 500
used CPU  = 320

remaining = 180 CPU
```

現在のNode実績から、

```text
Node profile:

p25 CPU = 7.5
p25 Memory = 30Gi
p25 Pods = 100
```

なら、

```text
180 / 7.5
= 24 Node
```

です。

Memory側が、

```text
NodePool remaining Memory = 400Gi

400 / 30
= 13 Node
```

なら、

```text
Karpenter additional nodes
= min(24, 13)
= 13 Node
```

です。

---

# 7. さらにPod単位に変換

そして、

```text
1 Node
≈ 100 Pod slots
```

なら、

```text
13 Node × 100
= 1,300 Pod slots
```

……ではまだダメです。

ここでも**対象PodのCPU/MEM requestを考慮**します。

例えば、

```text
Node profile:

CPU       7.5
Memory    30Gi
Pod slots 100
```

対象Pod：

```text
CPU       500m
Memory    1Gi
```

なら、

```text
CPU
7.5 / 0.5
= 15

Memory
30 / 1
= 30

Pod slots
100
```

なので、

```text
1 Node = 15 Pod
```

です。

したがって、

```text
13 Node × 15
= 195 Pod
```

となります。

これがかなり重要です。

---

# 8. `ProjectedCapacity` を追加する

ここまでをまとめるクラスを追加します。

```ruby
# frozen_string_literal: true

module ClusterCapacity

  class ProjectedCapacity

    def initialize(
      pod_cpu:,
      pod_memory:,
      current_capacity:,
      node_profile:,
      additional_nodes: 0
    )
      @pod_cpu =
        Quantity.cpu(pod_cpu)

      @pod_memory =
        Quantity.memory(pod_memory)

      @current =
        current_capacity

      @profile =
        node_profile

      @additional_nodes =
        additional_nodes
    end

    def calculate
      current =
        current_pods

      projected_node =
        pods_per_node

      future =
        projected_node *
        @additional_nodes

      {
        current_pods: current,

        pods_per_node: projected_node,

        additional_nodes:
          @additional_nodes,

        additional_pods:
          future,

        total_pods:
          current + future
      }
    end

    private

    def current_pods
      cpu =
        (
          @current[:total][:cpu] /
          @pod_cpu
        ).floor

      memory =
        (
          @current[:total][:memory] /
          @pod_memory
        ).floor

      pods =
        @current[:total][:pods]

      [
        cpu,
        memory,
        pods
      ].min
    end

    def pods_per_node
      cpu =
        (
          @profile[:cpu] /
          @pod_cpu
        ).floor

      memory =
        (
          @profile[:memory] /
          @pod_memory
        ).floor

      pods =
        @profile[:pods]

      [
        cpu,
        memory,
        pods
      ].min
    end
  end
end
```

---

# 9. 最終Estimator

これで前回の `Estimator` をかなりシンプルにできます。

```ruby
# frozen_string_literal: true

module ClusterCapacity

  class Estimator

    def initialize(
      pod_cpu:,
      pod_memory:,
      kubernetes_capacity:,
      node_profile:,
      additional_nodes: 0,
      aws_capacity: nil,
      safety_factor: 0.8
    )
      @pod_cpu = pod_cpu
      @pod_memory = pod_memory

      @kubernetes =
        kubernetes_capacity

      @node_profile =
        node_profile

      @additional_nodes =
        additional_nodes

      @aws =
        aws_capacity

      @safety_factor =
        safety_factor
    end

    def calculate
      projected =
        ProjectedCapacity.new(
          pod_cpu: @pod_cpu,
          pod_memory: @pod_memory,
          current_capacity: @kubernetes,
          node_profile: @node_profile,
          additional_nodes: @additional_nodes
        ).calculate

      candidates = {
        kubernetes: projected[:total_pods]
      }

      if @aws
        candidates[:aws] =
          aws_pod_capacity
      end

      raw =
        candidates.values.min

      safe =
        (raw * @safety_factor).floor

      {
        estimated_available_pods: safe,

        raw_estimate: raw,

        limiting_factor:
          candidates.min_by { |_key, value| value }.first,

        candidates: candidates,

        projected: projected,

        safety_factor: @safety_factor
      }
    end

    private

    def aws_pod_capacity
      candidates = []

      if @aws.dig(:vcpu, :remaining)
        candidates << (
          @aws[:vcpu][:remaining] *
          CPU_MILLI /
          Quantity.cpu(@pod_cpu)
        ).floor
      end

      if @aws.dig(:subnet, :available_ips)
        candidates << @aws[:subnet][:available_ips]
      end

      return Float::INFINITY if candidates.empty?

      candidates.min
    end
  end
end
```

---

# 10. ただしAWSの場合、ここをもう一段改善する

上の実装だと、

```text
Karpenter additional nodes
```

をNodePool limitだけから出しています。

しかしAWS側にも、

```text
AWS quota
Subnet IP
```

があります。

したがって最終的な「追加Node数」は、

```text
NodePool CPU
NodePool Memory
NodePool node limit
AWS vCPU quota
Subnet IP
```

の全部から計算するべきです。

そこで `NodeExpansionEstimator` を1つ追加すると綺麗です。

---

# 11. `NodeExpansionEstimator`

```ruby
# frozen_string_literal: true

module ClusterCapacity

  class NodeExpansionEstimator

    def initialize(
      node_profile:,
      karpenter_capacity:,
      aws_capacity: nil
    )
      @profile =
        node_profile

      @karpenter =
        karpenter_capacity

      @aws =
        aws_capacity
    end

    def calculate
      candidates = {}

      # ---------------------------------------------------------------
      # Karpenter CPU
      # ---------------------------------------------------------------

      if @karpenter.dig(:cpu, :remaining)

        candidates[:nodepool_cpu] =
          (
            @karpenter[:cpu][:remaining] /
            @profile[:cpu]
          ).floor
      end

      # ---------------------------------------------------------------
      # Karpenter Memory
      # ---------------------------------------------------------------

      if @karpenter.dig(:memory, :remaining)

        candidates[:nodepool_memory] =
          (
            @karpenter[:memory][:remaining] /
            @profile[:memory]
          ).floor
      end

      # ---------------------------------------------------------------
      # NodePool node limit
      # ---------------------------------------------------------------

      if @karpenter.dig(:nodes, :remaining)

        candidates[:nodepool_nodes] =
          @karpenter[:nodes][:remaining]
      end

      # ---------------------------------------------------------------
      # AWS vCPU quota
      # ---------------------------------------------------------------

      if @aws&.dig(:vcpu, :remaining)

        candidates[:aws_vcpu] =
          (
            @aws[:vcpu][:remaining] /
            (@profile[:cpu] / CPU_MILLI)
          ).floor
      end

      # ---------------------------------------------------------------
      # AWS subnet
      #
      # ここはNodeあたり何IP消費するかを
      # profileに持たせるとさらに良い。
      #
      # 今回は conservative に
      # 1 Node = 1 IP とするのではなく、
      # pod capacityベースで扱う。
      # ---------------------------------------------------------------

      {
        candidates: candidates,

        additional_nodes:
          candidates.empty? ?
            0 :
            candidates.values.min,

        limiting_factor:
          candidates.empty? ?
            nil :
            candidates.min_by { |_k, v| v }.first
      }
    end
  end
end
```

---

# 12. NodeProfileに「Pod requestあたりのcapacity」を持たせる

ここまでくると、最終的に欲しいのは、

```ruby
profile = {
  cpu: 7_500,
  memory: 30.gigabytes,
  pods: 100
}
```

です。

するとPod requestが、

```text
500m / 1Gi
```

なら、

```text
CPU      15
Memory   30
Pod      100
---------
実効     15 Pod
```

となります。

つまり、

```ruby
def pods_per_node(profile, pod_cpu, pod_memory)
  [
    profile[:cpu] / Quantity.cpu(pod_cpu),
    profile[:memory] / Quantity.memory(pod_memory),
    profile[:pods]
  ].min.floor
end
```

で済みます。

---

# 13. 実際の利用コード

AWS + Karpenterならこうなります。

```ruby
client =
  ClusterCapacity::KubernetesClient.new

# ------------------------------------------------------------
# Kubernetes current state
# ------------------------------------------------------------

nodes =
  client.get("/api/v1/nodes")["items"]

pods =
  client.get("/api/v1/pods")["items"]

kubernetes =
  ClusterCapacity::KubernetesCapacity.new(
    client: client
  ).calculate

# ------------------------------------------------------------
# Node profile
# ------------------------------------------------------------

profile_result =
  ClusterCapacity::NodeProfileEstimator.new(
    nodes: nodes,
    pods: pods,

    nodepool_name: "default",

    # p25 = conservative
    percentile: 25,

    min_nodes: 2
  ).estimate

profile = {
  cpu: profile_result[:cpu][:value],
  memory: profile_result[:memory][:value],
  pods: profile_result[:pods][:value]
}

# ------------------------------------------------------------
# Karpenter
# ------------------------------------------------------------

karpenter =
  ClusterCapacity::KarpenterCapacity.new(
    client: client,
    nodepool_name: "default",
    nodes: nodes,
    pods: pods
  ).calculate

# ------------------------------------------------------------
# AWS
# ------------------------------------------------------------

aws =
  ClusterCapacity::AwsCapacity.new(
    region: "ap-northeast-1",

    subnet_ids: [
      "subnet-aaa",
      "subnet-bbb"
    ]
  ).calculate

# ------------------------------------------------------------
# Additional Node count
# ------------------------------------------------------------

expansion =
  ClusterCapacity::NodeExpansionEstimator.new(
    node_profile: profile,
    karpenter_capacity: karpenter,
    aws_capacity: aws
  ).calculate

# ------------------------------------------------------------
# Final
# ------------------------------------------------------------

result =
  ClusterCapacity::Estimator.new(
    pod_cpu: "500m",
    pod_memory: "1Gi",

    kubernetes_capacity: kubernetes,

    node_profile: profile,

    additional_nodes:
      expansion[:additional_nodes],

    aws_capacity: aws,

    safety_factor: 0.8
  ).calculate

pp result
```

---

# 14. 例えばこういう結果になる

```ruby
{
  estimated_available_pods: 156,

  raw_estimate: 195,

  limiting_factor: :aws,

  candidates: {
    kubernetes: 195,
    aws: 210
  },

  projected: {
    current_pods: 35,
    pods_per_node: 15,
    additional_nodes: 13,
    additional_pods: 195,
    total_pods: 230
  },

  safety_factor: 0.8
}
```

つまり、

```text
現在空いているcapacity      35 Pod

Karpenterで追加可能Node      13 Node

1 Nodeあたり実効capacity      15 Pod

追加可能capacity             195 Pod

理論上                        230 Pod

AWS側制約                    210 Pod

最終                          210 Pod

Safety factor 80%
                           ↓

ユーザーに見せる数字          168 Pod
```

という感じです。

---

# 15. ただし、ここで一つ大事な修正

上記の `NodeExpansionEstimator` ではAWS subnet IPをNode数に変換していません。

これは**意図的**です。

Subnetの、

```text
available_ip_address_count = 500
```

だけから、

```text
あと何Node作れるか
```

を正確に出すことはできないからです。

例えば、

```text
Node A → 10 IP
Node B → 20 IP
Node C → 40 IP
```

とバラつきます。

そこで実用版では、NodeProfileに、

```ruby
ip_addresses_per_node
```

を追加するのがよいです。

---

# 16. `NodeNetworkProfile`

AWS VPC CNIなら、実際のPod IP使用数を観測して、

```text
1 Nodeあたり平均 18 IP
```

などを出します。

ただしPod IPをKubernetes APIだけから正確に取るのはAWS VPC CNI固有情報に依存するので、AWS adapter側でやります。

つまり、

```text
NodeProfileEstimator
        │
        ├── CPU
        ├── Memory
        └── Pod slots
             
AwsNodeNetworkProfile
        │
        └── IP / Node
```

と分ける。

例えば、

```ruby
{
  ip_per_node: 20
}
```

なら、

```text
Subnet remaining IP = 500

500 / 20
= 25 Node
```

と推定できます。

そして、

```text
NodePool       20 Node
AWS quota      18 Node
Subnet         25 Node
```

なので、

```text
追加可能Node = 18
```

となります。

---

# 17. オンプレではどうなるか

ここがこの設計のメリットです。

オンプレでは、

```ruby
aws_capacity = nil
```

でいい。

例えば、

```ruby
expansion =
  ClusterCapacity::NodeExpansionEstimator.new(
    node_profile: profile,
    karpenter_capacity: nil,
    aws_capacity: nil
  ).calculate
```

というのはあまり意味がないので、オンプレでは**autoscalerから追加可能Node数を渡す**設計にします。

例えばCluster Autoscalerを使っているなら、

```ruby
autoscaler_capacity = {
  additional_nodes: 10
}
```

として、

```ruby
NodeExpansionEstimator
```

に渡せばいい。

---

# 18. ここまでやるとadapter設計が綺麗

最終的には、

```text
                   Capacity Provider
                         │
          ┌──────────────┼──────────────┐
          │              │              │
       Karpenter    Cluster Autoscaler   Static
          │              │              │
          ▼              ▼              ▼
       AWS/EKS         On-prem         On-prem
```

という構造にできます。

例えば、

```ruby
provider.additional_node_capacity
```

が、

```ruby
{
  nodes: 13,
  confidence: :medium
}
```

を返す。

EstimatorはAWSかオンプレかを知りません。

---

# 19. 最終的に僕ならこのAPIにする

Rubyアプリ側にはAWS/Kubernetesの詳細を見せず、

```ruby
capacity =
  ClusterCapacity::Service.new(
    pod_cpu: "500m",
    pod_memory: "1Gi",
    nodepool: "default"
  ).estimate
```

だけにします。

返り値は、

```ruby
{
  available_pods: 156,

  confidence: :medium,

  limiting_factor: :aws_vcpu,

  current: {
    pods: 35
  },

  expandable: {
    nodes: 13,
    pods_per_node: 15,
    pods: 195
  },

  constraints: {
    nodepool_cpu: 200,
    nodepool_memory: 300,
    aws_vcpu: 210,
    subnet: 250
  },

  safety_factor: 0.8
}
```

という形。

そしてアプリ側は、

```ruby
if capacity[:available_pods] < requested_pods
  # capacity不足
end
```

だけを見る。

---

## この方式の重要なメリット

今回の `NodeProfileEstimator` を入れると、最初の単純な

```text
NodePool limit / Pod request
```

から、

```text
             実際のNode
                 ↓
        allocatableを観測
                 ↓
      DaemonSetコストを観測
                 ↓
        p25 Node Profile
                 ↓
      「Node 1台 ≒ 15 Pod」
                 ↓
       追加可能Node数を推定
                 ↓
        追加可能Pod数を算出
                 ↓
       AWS quota / IPでcap
                 ↓
        safety factor
                 ↓
     「安全側で約156 Pod」
```

になります。

これは「正確なschedulerシミュレーション」ではありませんが、**運用上のcapacity indicatorとしてはかなり現実的なところ**です。

特に `percentile: 25` と `safety_factor: 0.8` の2段階で保守的にしているのがポイントです。KarpenterのNodePool limitはeventually consistentなので、capacityの数字を厳密な保証値として扱わないことも重要です。([karpenter.sh](https://karpenter.sh/docs/concepts/nodepools/?utm_source=chatgpt.com))

なお、次に仕上げるなら **`nodeSelector / nodeAffinity / taints / tolerations / topology` をNodeProfileの候補Node選択に反映**させるのが最も効果があります。これを入れると「クラスタ全体では200 Pod空いているが、このPodを載せられるcapacityは32 Pod」というケースまで扱えるようになります。
