ここまでやるなら、単純な「CPU/MEMの最小値」から一段進めて、

1. **Kubernetes共通部分**

   * Nodeの `allocatable`
   * 実際にNodeへ割り当てられているPodの `requests`
   * Init Containerのeffective request
   * Pod overhead
   * Nodeの `allocatable.pods`
   * NotReady / cordoned Nodeの除外
2. **Karpenter部分**

   * `NodePool.spec.limits`
   * `NodePool.status.resources`
   * 現在NodePoolが消費しているcapacity
   * 今後追加可能なcapacity
3. **AWS部分**

   * EC2 vCPU quota
   * 現在のEC2 vCPU使用量
   * Subnet available IP
4. **オンプレ部分**

   * AWSの制約は一切入れない
   * 現在Nodeのcapacityをそのまま利用
   * 必要なら「追加Nodeを何台増やせるか」を外部設定で与える

という構造にするのがよいです。

特にKubernetesのschedulerは、単純なcontainer requestの合計ではなく、**Init Containerを含めたeffective request**を使います。またPod overheadもschedulerのresource calculationに含まれます。([Kubernetes][1])

Karpenterについては、現在のNodePoolには `spec.limits` と `status.resources` があり、後者が現在NodePoolにprovisionされているresource量です。([Karpenter][2])

---

# 提案する構造

```text
                    ┌──────────────────────┐
                    │ Kubernetes API       │
                    │                      │
                    │ Nodes                │
                    │ Pods                 │
                    │ NodePool (optional)  │
                    └──────────┬───────────┘
                               │
                               ▼
                    ┌──────────────────────┐
                    │ KubernetesCapacity   │
                    │                      │
                    │ current CPU          │
                    │ current Memory       │
                    │ current Pod slots    │
                    └──────────┬───────────┘
                               │
                ┌──────────────┴──────────────┐
                │                             │
          Karpenter                       On-prem
                │                             │
                ▼                             │
       NodePool remaining                    │
                │                             │
                ▼                             │
        ┌───────────────┐                     │
        │ AWS           │                     │
        │               │                     │
        │ vCPU quota    │                     │
        │ subnet IP     │                     │
        └───────┬───────┘                     │
                │                             │
                └──────────────┬──────────────┘
                               ▼
                       CapacityEstimator
                               │
                               ▼
                    estimated_available_pods
```

この設計なら、**AWS依存コードをかなり綺麗に切り離せます**。

---

# 実装

今回はKubernetes APIへのアクセスに `kubeclient` の抽象化に依存しすぎないよう、**Kubernetes REST APIを直接叩く薄いクライアント**にしています。

依存はAWS SDKだけです。

```ruby
# Gemfile

gem "aws-sdk-ec2"
gem "aws-sdk-servicequotas"
```

Kubernetes APIはPod内ならServiceAccount tokenを利用します。

---

## `cluster_capacity.rb`

```ruby
# frozen_string_literal: true

require "json"
require "net/http"
require "openssl"
require "uri"

require "aws-sdk-ec2"
require "aws-sdk-servicequotas"


module ClusterCapacity

  CPU_MILLI = 1_000

  # --------------------------------------------------------------------------
  # Kubernetes resource quantity
  # --------------------------------------------------------------------------

  module Quantity
    MEMORY_UNITS = {
      "Ki" => 1024,
      "Mi" => 1024**2,
      "Gi" => 1024**3,
      "Ti" => 1024**4,
      "Pi" => 1024**5,
      "Ei" => 1024**6
    }.freeze

    DECIMAL_UNITS = {
      "K" => 1_000,
      "M" => 1_000**2,
      "G" => 1_000**3,
      "T" => 1_000**4,
      "P" => 1_000**5,
      "E" => 1_000**6
    }.freeze

    module_function

    def cpu(value)
      return 0.0 if value.nil?

      value = value.to_s.strip

      case value
      when /\A([\d.]+)n\z/
        Regexp.last_match(1).to_f / 1_000_000.0

      when /\A([\d.]+)u\z/
        Regexp.last_match(1).to_f / 1_000.0

      when /\A([\d.]+)m\z/
        Regexp.last_match(1).to_f

      else
        value.to_f * CPU_MILLI
      end
    end

    def memory(value)
      return 0 if value.nil?

      value = value.to_s.strip

      MEMORY_UNITS.each do |suffix, multiplier|
        if value.end_with?(suffix)
          return (
            value.delete_suffix(suffix).to_f * multiplier
          ).to_i
        end
      end

      DECIMAL_UNITS.each do |suffix, multiplier|
        if value.end_with?(suffix)
          return (
            value.delete_suffix(suffix).to_f * multiplier
          ).to_i
        end
      end

      value.to_i
    end
  end


  # --------------------------------------------------------------------------
  # Kubernetes REST client
  # --------------------------------------------------------------------------

  class KubernetesClient

    DEFAULT_HOST = "https://kubernetes.default.svc"

    def initialize(
      host: ENV.fetch("KUBERNETES_SERVICE_HOST", nil),
      port: ENV.fetch("KUBERNETES_SERVICE_PORT_HTTPS", "443"),
      token_file: "/var/run/secrets/kubernetes.io/serviceaccount/token",
      ca_file: "/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"
    )
      host ||= DEFAULT_HOST

      @base_url =
        if host.start_with?("http")
          host
        else
          "https://#{host}:#{port}"
        end

      @token = File.read(token_file).strip

      @ca_file = ca_file
    end

    def get(path)
      request(:get, path)
    end

    private

    def request(method, path)
      uri = URI.join(@base_url, path)

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true

      if @ca_file && File.exist?(@ca_file)
        http.ca_file = @ca_file
        http.verify_mode = OpenSSL::SSL::VERIFY_PEER
      else
        http.verify_mode = OpenSSL::SSL::VERIFY_PEER
      end

      http.open_timeout = 5
      http.read_timeout = 10

      request =
        case method
        when :get
          Net::HTTP::Get.new(uri)
        else
          raise ArgumentError, "Unsupported HTTP method"
        end

      request["Authorization"] = "Bearer #{@token}"
      request["Accept"] = "application/json"

      response = http.request(request)

      unless response.is_a?(Net::HTTPSuccess)
        raise(
          "Kubernetes API error: #{response.code} #{response.body}"
        )
      end

      JSON.parse(response.body)
    end
  end


  # --------------------------------------------------------------------------
  # Pod resource calculation
  # --------------------------------------------------------------------------

  class PodResources

    TERMINAL_PHASES = %w[
      Succeeded
      Failed
    ].freeze

    def self.calculate(pod)
      return zero if terminal?(pod)

      spec = pod.fetch("spec", {})

      containers =
        spec.fetch("containers", [])

      init_containers =
        spec.fetch("initContainers", [])

      regular = sum_containers(containers)
      init = max_containers(init_containers)

      cpu =
        [regular[:cpu], init[:cpu]].max

      memory =
        [regular[:memory], init[:memory]].max

      overhead =
        spec
          .fetch("overhead", {})
          .transform_keys(&:to_s)

      cpu += Quantity.cpu(overhead["cpu"])
      memory += Quantity.memory(overhead["memory"])

      {
        cpu: cpu,
        memory: memory
      }
    end

    def self.terminal?(pod)
      TERMINAL_PHASES.include?(
        pod.dig("status", "phase")
      )
    end

    def self.sum_containers(containers)
      containers.reduce(zero) do |total, container|
        requests =
          container
            .fetch("resources", {})
            .fetch("requests", {})

        {
          cpu: total[:cpu] + Quantity.cpu(requests["cpu"]),
          memory: total[:memory] + Quantity.memory(requests["memory"])
        }
      end
    end

    def self.max_containers(containers)
      containers.reduce(zero) do |max, container|
        requests =
          container
            .fetch("resources", {})
            .fetch("requests", {})

        {
          cpu: [max[:cpu], Quantity.cpu(requests["cpu"])].max,
          memory: [
            max[:memory],
            Quantity.memory(requests["memory"])
          ].max
        }
      end
    end

    def self.zero
      {
        cpu: 0.0,
        memory: 0
      }
    end

    private_class_method :sum_containers
    private_class_method :max_containers
    private_class_method :zero
  end


  # --------------------------------------------------------------------------
  # Kubernetes current capacity
  # --------------------------------------------------------------------------

  class KubernetesCapacity

    def initialize(
      client:,
      node_selector: nil
    )
      @client = client
      @node_selector = node_selector
    end

    def calculate
      nodes = list_nodes
      pods = list_pods

      pods_by_node =
        pods
          .select { |pod| PodResources.terminal?(pod) == false }
          .group_by { |pod| pod.dig("spec", "nodeName") }

      node_results = []

      nodes.each do |node|
        next unless schedulable?(node)
        next unless selected_node?(node)

        node_name =
          node.dig("metadata", "name")

        allocatable =
          node.dig("status", "allocatable") || {}

        cpu =
          Quantity.cpu(allocatable["cpu"])

        memory =
          Quantity.memory(allocatable["memory"])

        pod_slots =
          allocatable.fetch("pods", "0").to_i

        node_pods =
          pods_by_node.fetch(node_name, [])

        requested =
          node_pods.reduce(
            cpu: 0.0,
            memory: 0,
            pods: 0
          ) do |total, pod|

            resources =
              PodResources.calculate(pod)

            {
              cpu: total[:cpu] + resources[:cpu],
              memory: total[:memory] + resources[:memory],
              pods: total[:pods] + 1
            }
          end

        free_cpu =
          [cpu - requested[:cpu], 0].max

        free_memory =
          [memory - requested[:memory], 0].max

        free_pods =
          [pod_slots - requested[:pods], 0].max

        node_results << {
          name: node_name,

          allocatable: {
            cpu: cpu,
            memory: memory,
            pods: pod_slots
          },

          requested: requested,

          free: {
            cpu: free_cpu,
            memory: free_memory,
            pods: free_pods
          }
        }
      end

      {
        nodes: node_results,

        total: {
          cpu: node_results.sum { |n| n[:free][:cpu] },
          memory: node_results.sum { |n| n[:free][:memory] },
          pods: node_results.sum { |n| n[:free][:pods] }
        }
      }
    end

    private

    def list_nodes
      response =
        @client.get(
          "/api/v1/nodes"
        )

      response.fetch("items", [])
    end

    def list_pods
      response =
        @client.get(
          "/api/v1/pods"
        )

      response.fetch("items", [])
    end

    def schedulable?(node)
      conditions =
        node
          .dig("status", "conditions") || []

      ready =
        conditions.find do |condition|
          condition["type"] == "Ready"
        end

      return false unless ready&.fetch("status") == "True"

      unschedulable =
        node.dig(
          "spec",
          "unschedulable"
        )

      !unschedulable
    end

    def selected_node?(node)
      return true if @node_selector.nil?

      labels =
        node.dig("metadata", "labels") || {}

      @node_selector.all? do |key, value|
        labels[key] == value
      end
    end
  end


  # --------------------------------------------------------------------------
  # Karpenter
  # --------------------------------------------------------------------------

  class KarpenterCapacity

    def initialize(
      client:,
      nodepool_name:
    )
      @client = client
      @nodepool_name = nodepool_name
    end

    def calculate
      nodepool =
        @client.get(
          "/apis/karpenter.sh/v1/nodepools/#{@nodepool_name}"
        )

      spec_limits =
        nodepool
          .dig("spec", "limits") || {}

      status_resources =
        nodepool
          .dig("status", "resources") || {}

      result = {}

      if spec_limits["cpu"]
        limit_cpu =
          Quantity.cpu(spec_limits["cpu"])

        used_cpu =
          Quantity.cpu(status_resources["cpu"])

        result[:cpu] = {
          limit: limit_cpu,
          used: used_cpu,
          remaining: [
            limit_cpu - used_cpu,
            0
          ].max
        }
      end

      if spec_limits["memory"]
        limit_memory =
          Quantity.memory(spec_limits["memory"])

        used_memory =
          Quantity.memory(status_resources["memory"])

        result[:memory] = {
          limit: limit_memory,
          used: used_memory,
          remaining: [
            limit_memory - used_memory,
            0
          ].max
        }
      end

      result[:nodes] =
        if spec_limits["nodes"]
          {
            limit: spec_limits["nodes"].to_i,
            used: nodepool.dig("status", "nodes").to_i,
            remaining: [
              spec_limits["nodes"].to_i -
                nodepool.dig("status", "nodes").to_i,
              0
            ].max
          }
        end

      result[:ready] =
        nodepool
          .dig("status", "conditions")
          &.find { |c| c["type"] == "Ready" }
          &.fetch("status", "False") == "True"

      result
    end
  end


  # --------------------------------------------------------------------------
  # AWS capacity
  # --------------------------------------------------------------------------

  class AwsCapacity

    DEFAULT_ON_DEMAND_QUOTA =
      "L-1216C47A"

    def initialize(
      region:,
      subnet_ids: [],
      quota_code: DEFAULT_ON_DEMAND_QUOTA,
      capacity_type: :on_demand
    )
      @region = region
      @subnet_ids = subnet_ids
      @quota_code = quota_code
      @capacity_type = capacity_type

      @ec2 =
        Aws::EC2::Client.new(
          region: region
        )

      @quotas =
        Aws::ServiceQuotas::Client.new(
          region: region
        )
    end

    def calculate
      {
        vcpu: vcpu_capacity,
        subnet: subnet_capacity
      }
    end

    private

    def vcpu_capacity
      quota =
        @quotas.get_service_quota(
          service_code: "ec2",
          quota_code: @quota_code
        ).quota

      quota_vcpu =
        quota.value.to_f

      used_vcpu =
        running_vcpu

      {
        quota: quota_vcpu,
        used: used_vcpu,
        remaining: [
          quota_vcpu - used_vcpu,
          0
        ].max
      }
    end

    def running_vcpu
      instances = []

      token = nil

      loop do
        response =
          @ec2.describe_instances(
            filters: [
              {
                name: "instance-state-name",
                values: ["running"]
              }
            ],
            next_token: token
          )

        response.reservations.each do |reservation|
          reservation.instances.each do |instance|

            spot =
              instance.instance_lifecycle == "spot"

            if @capacity_type == :spot
              next unless spot
            else
              next if spot
            end

            instances << instance
          end
        end

        token = response.next_token

        break unless token
      end

      return 0 if instances.empty?

      types =
        instances
          .map(&:instance_type)
          .uniq

      response =
        @ec2.describe_instance_types(
          instance_type_names: types
        )

      vcpu_by_type = {}

      response.instance_types.each do |type|
        vcpu_by_type[type.instance_type] =
          type.v_cpu_info.default_v_cpus
      end

      instances.sum do |instance|
        vcpu_by_type.fetch(
          instance.instance_type,
          0
        )
      end
    end

    def subnet_capacity
      return {
        available_ips: Float::INFINITY
      } if @subnet_ids.empty?

      response =
        @ec2.describe_subnets(
          subnet_ids: @subnet_ids
        )

      available =
        response.subnets.sum do |subnet|
          subnet.available_ip_address_count || 0
        end

      {
        available_ips: available
      }
    end
  end


  # --------------------------------------------------------------------------
  # Final estimator
  # --------------------------------------------------------------------------

  class Estimator

    def initialize(
      pod_cpu:,
      pod_memory:,
      kubernetes_capacity:,
      karpenter_capacity: nil,
      aws_capacity: nil,
      safety_factor: 0.8
    )
      @pod_cpu =
        Quantity.cpu(pod_cpu)

      @pod_memory =
        Quantity.memory(pod_memory)

      @kubernetes =
        kubernetes_capacity

      @karpenter =
        karpenter_capacity

      @aws =
        aws_capacity

      @safety_factor =
        safety_factor.to_f

      raise ArgumentError,
            "safety_factor must be 0..1" unless
        (0.0..1.0).cover?(@safety_factor)
    end

    def calculate
      current =
        current_capacity

      expansion =
        expansion_capacity

      raw =
        [
          current[:cpu_pods] + expansion[:cpu_pods],
          current[:memory_pods] + expansion[:memory_pods],
          current[:pod_slots] + expansion[:pod_slots]
        ].min

      aws_limited =
        aws_limit

      result =
        [raw, aws_limited].min

      result =
        (result * @safety_factor).floor

      {
        estimated_available_pods: result,

        raw_estimate: [
          current[:cpu_pods] + expansion[:cpu_pods],
          current[:memory_pods] + expansion[:memory_pods],
          current[:pod_slots] + expansion[:pod_slots]
        ].min,

        limiting_factors: {
          kubernetes_cpu: current[:cpu_pods] + expansion[:cpu_pods],
          kubernetes_memory: current[:memory_pods] + expansion[:memory_pods],
          pod_slots: current[:pod_slots] + expansion[:pod_slots],
          aws: aws_limited
        },

        current: current,
        expansion: expansion
      }
    end

    private

    def current_capacity
      total =
        @kubernetes[:total]

      {
        cpu_pods:
          (total[:cpu] / @pod_cpu).floor,

        memory_pods:
          (total[:memory] / @pod_memory).floor,

        pod_slots:
          total[:pods]
      }
    end

    def expansion_capacity
      return {
        cpu_pods: 0,
        memory_pods: 0,
        pod_slots: 0
      } unless @karpenter

      cpu =
        @karpenter.dig(:cpu, :remaining)

      memory =
        @karpenter.dig(:memory, :remaining)

      {
        cpu_pods:
          cpu ?
            (cpu / @pod_cpu).floor :
            0,

        memory_pods:
          memory ?
            (memory / @pod_memory).floor :
            0,

        # NodePoolのresource limitだけでは
        # maxPodsを正確に算出できないため0。
        #
        # 後述の「projected node capacity」を設定する場合
        # ここを拡張する。
        pod_slots: 0
      }
    end

    def aws_limit
      return Float::INFINITY unless @aws

      candidates = []

      vcpu =
        @aws.dig(:vcpu, :remaining)

      if vcpu
        candidates << (
          vcpu * CPU_MILLI / @pod_cpu
        ).floor
      end

      ips =
        @aws.dig(:subnet, :available_ips)

      candidates << ips if ips

      return Float::INFINITY if candidates.empty?

      candidates.min
    end
  end
end
```

---

# 使い方

## AWS + Karpenter

```ruby
client =
  ClusterCapacity::KubernetesClient.new

k8s =
  ClusterCapacity::KubernetesCapacity.new(
    client: client
  ).calculate

karpenter =
  ClusterCapacity::KarpenterCapacity.new(
    client: client,
    nodepool_name: "default"
  ).calculate

aws =
  ClusterCapacity::AwsCapacity.new(
    region: "ap-northeast-1",
    subnet_ids: [
      "subnet-aaa",
      "subnet-bbb",
      "subnet-ccc"
    ]
  ).calculate

result =
  ClusterCapacity::Estimator.new(
    pod_cpu: "500m",
    pod_memory: "1Gi",

    kubernetes_capacity: k8s,
    karpenter_capacity: karpenter,
    aws_capacity: aws,

    # 20%程度の余裕を残す
    safety_factor: 0.8
  ).calculate

pp result
```

---

# オンプレの場合

ここが今回の改善ポイントです。

オンプレなら、

```ruby
client =
  ClusterCapacity::KubernetesClient.new

k8s =
  ClusterCapacity::KubernetesCapacity.new(
    client: client
  ).calculate

result =
  ClusterCapacity::Estimator.new(
    pod_cpu: "500m",
    pod_memory: "1Gi",

    kubernetes_capacity: k8s,

    karpenter_capacity: nil,
    aws_capacity: nil,

    safety_factor: 0.8
  ).calculate

pp result
```

これだけです。

つまりAWS固有の、

```text
AWS vCPU quota
Subnet IP
Karpenter NodePool
```

は全部無視され、

```text
現在のKubernetes Node
        ↓
allocatable
        ↓
現在のPod requestsを差し引く
        ↓
CPU/MEM/Pod slots
        ↓
Pod requestで割る
```

になります。

---

# ここで以前の実装より重要な改善

例えばNodeが、

```text
allocatable:

CPU      8
Memory   32Gi
Pods     110
```

だったとします。

実際に、

```text
Pod A
CPU      2
Memory   4Gi

Pod B
CPU      1
Memory   8Gi
```

が動いている。

すると単純計算では、

```text
CPU:
8 - 3 = 5

Memory:
32 - 12 = 20Gi

Pods:
110 - 2 = 108
```

です。

500m / 1Gi Podなら、

```text
CPU      10 Pod
Memory   20 Pod
Pod slot 108 Pod
```

なので、

```text
current capacity = 10 Pod
```

です。

**CPUがボトルネック**だと分かります。

---

# Init Containerも正しく計算

例えば、

```yaml
containers:
  - resources:
      requests:
        cpu: "500m"
        memory: "1Gi"

  - resources:
      requests:
        cpu: "500m"
        memory: "1Gi"

initContainers:
  - resources:
      requests:
        cpu: "2"
        memory: "4Gi"
```

の場合、

```text
通常container合計

CPU    1
MEM    2Gi

Init

CPU    2
MEM    4Gi
```

なので、Podのeffective requestは、

```text
CPU    2
MEM    4Gi
```

です。

KubernetesのschedulerもこのルールでInit Containerの最大requestと通常containerの合計を比較します。([Kubernetes][3])

このため、最初の簡易版よりかなり実態に近くなります。

---

# Pod overheadも入れている

例えばRuntimeClassなどで、

```yaml
overhead:
  cpu: 10m
  memory: 16Mi
```

となっているPodなら、

```text
container request
+
pod overhead
```

として計算しています。

KubernetesでもPod overheadはschedulerがPod resource requestに追加して扱います。([Kubernetes][1])

---

# ただし、さらに重要な問題が1つある

ここまでやっても、

```text
estimated_available_pods = 360
```

が、

> 「任意のPodを360個追加できる」

という意味にはなりません。

例えば、

```yaml
nodeSelector:
  workload: gpu
```

というPodなら、CPUが100 vCPU空いている普通のNodeが100台あっても意味がありません。

同様に、

* taint / toleration
* nodeSelector
* nodeAffinity
* topology spread
* architecture
* zone
* GPU
* hugepages
* extended resources

などがあります。

KarpenterもNodePoolのrequirementsやtaintsを考慮してProvisioningするため、NodePoolに条件がある場合、単純なCPU capacityだけでは「そのPodが載るか」は判断できません。([Karpenter][2])

---

# そこで実運用では「Pod Profile」を渡す

例えばRuby側で、

```ruby
capacity =
  estimator.calculate(
    pod: {
      cpu: "500m",
      memory: "1Gi",

      node_selector: {
        "workload" => "api"
      }
    }
  )
```

という形にする。

そうすると、

```text
全Node
 ↓
nodeSelector/toleration/affinityで候補Nodeを絞る
 ↓
候補Nodeのallocatable
 ↓
Pod requestsを差し引く
 ↓
capacity
```

とできます。

今回のコードではそこまで複雑にしていませんが、**この拡張ポイントは `KubernetesCapacity` に置く**のがよいです。

---

# Karpenterについてはさらに一段改善できる

現在のコードでは、

```text
NodePool limit
-
NodePool status.resources
=
追加可能CPU/MEM
```

を、

```text
Pod request
```

で割っています。

これは以前よりかなり良いですが、まだ少し過大評価します。

例えば、

```text
NodePool remaining CPU = 100 vCPU
NodePool remaining MEM = 200 GiB
```

だから、

```text
500m CPU / 1Gi Pod
```

なら、

```text
CPU → 200 Pod
MEM → 200 Pod
```

と出ます。

しかしKarpenterが実際に作るNodeには、

```text
system-reserved
kube-reserved
DaemonSet
maxPods
ENI
```

などがあります。

KarpenterのNodeClaimにも `status.capacity` と `status.allocatable` があり、後者はsystem reservation等を差し引いた「実際にPod schedulingに使えるcapacity」です。([Karpenter][4])

---

# そこで「Observed Node Profile」を使うのがおすすめ

Karpenterが現在10 Node動かしているなら、

```text
NodePool default

Node 1 allocatable:
  CPU    7.8
  MEM    30Gi
  Pods   110

Node 2:
  CPU    7.8
  MEM    30Gi
  Pods   110

...

Node 10:
  CPU    15.8
  MEM    62Gi
  Pods   110
```

のような情報があります。

ここから、

```text
median allocatable CPU
median allocatable MEM
median allocatable Pods
```

を取って、

```text
NodePool remaining CPU = 100 vCPU

median node CPU = 8 vCPU

→ 約12.5 Node
```

と推定します。

さらに、

```text
1 Nodeあたり実効Pod capacity
```

を観測して、

```text
12 Node × 例えば16 Pod
= 約192 Pod
```

とする。

これは単純な

```text
100 / 0.5 = 200 Pod
```

より現実に近くなります。

---

# さらに良いのは「packing efficiency」を学習する

実運用ならこれがかなり面白いです。

例えば過去のNodeについて、

```text
allocatable CPU       8
Pod requests CPU      7.2
```

なら、

```text
CPU utilization by request = 90%
```

です。

Memoryも、

```text
allocatable Memory     32Gi
Pod requests Memory    24Gi
```

なら、

```text
75%
```

です。

そこで、

```text
historical packing efficiency

CPU    82%
Memory 76%
Pods   91%
```

みたいな値を持って、

```text
future CPU capacity
× 0.82
```

とする。

これなら、

```text
NodePool remaining CPU = 100 vCPU

→ theoretical 200 pods

→ packing factor 0.82

→ 164 pods
```

となります。

**「厳密ではないけど、実際のクラスタの癖を反映した数字」**になります。

今回の用途なら、この方向が一番おすすめです。

---

# AWS IPについても同じ

Subnetの

```text
available_ip_address_count = 800
```

をそのまま

```text
800 Pods
```

とするのは粗いです。

VPC CNIの場合は、

```text
Subnet IP
  ↓
ENI / Prefix
  ↓
Node
  ↓
Pod
```

なので、Node単位のIP消費があります。

しかし実測できるので、

```text
NodePoolのNode 20台

平均Pod IP消費
= 32 IP / Node
```

のような実績値を取ることもできます。

すると、

```text
Subnet available IP = 800

800 / 32
≈ 25 Node相当
```

と推定できます。

さらにNode 1台あたり平均16 Podなら、

```text
25 × 16
= 400 Pod
```

という推定にできます。

これはかなり実用的です。

---

# 最終的にはこういう数値を返すのがおすすめ

Rubyアプリからは、

```ruby
{
  estimated_available_pods: 156,

  confidence: "medium",

  limiting_factor: "nodepool_cpu",

  pod_request: {
    cpu: "500m",
    memory: "1Gi"
  },

  capacity: {
    current: {
      cpu_pods: 42,
      memory_pods: 91,
      pod_slots: 180
    },

    expandable: {
      nodepool_cpu_pods: 190,
      nodepool_memory_pods: 230,
      aws_vcpu_pods: 210,
      subnet_ip_pods: 310
    }
  },

  safety_factor: 0.8,

  warnings: [
    "Karpenter capacity is eventually consistent",
    "Node affinity/toleration constraints are not fully simulated"
  ]
}
```

くらいが非常に使いやすいです。

---

## AWSとオンプレの違い

最終的な考え方はこうなります。

| 制約                 | EKS + Karpenter |                オンプレ |
| ------------------ | --------------: | ------------------: |
| 現在Node CPU         |               ○ |                   ○ |
| 現在Node Memory      |               ○ |                   ○ |
| Pod requests       |               ○ |                   ○ |
| Init Container     |               ○ |                   ○ |
| Pod overhead       |               ○ |                   ○ |
| maxPods            |               ○ |                   ○ |
| NodePool limit     |               ○ |                   — |
| NodePool usage     |               ○ |                   — |
| AWS vCPU quota     |               ○ |                   — |
| Subnet IP          |               ○ |                   — |
| Cluster Autoscaler |              任意 |                  任意 |
| 将来Node capacity    |   Karpenterから推定 | 外部設定/Autoscalerから推定 |

つまり、**Kubernetes部分を共通の土台にして、autoscaler/cloud-providerを上に載せる**のがポイントです。

Karpenterを使っていないオンプレでも、現在のNode capacityについては同じコードで計算できます。

---

### もう一段実用化するなら

僕なら次のバージョンでは、上記クラスに **`NodeProfileEstimator`** を追加します。

```text
過去/現在のNode
      ↓
Node allocatable
      ↓
DaemonSet等の実コスト
      ↓
1 Nodeあたりの実効Pod capacity
      ↓
median / p25
      ↓
「Karpenterが今後作るNode 1台あたり」
の推定capacity
      ↓
NodePool remaining resource
      ↓
AWS quota
      ↓
Subnet IP
      ↓
最終的な estimated_available_pods
```

これを入れると、**「理論上あと360 Pod」ではなく、「過去の実績を考慮すると安全側で約150 Pod」**のような数字が出せるようになります。

特にKarpenterはNodePoolの`limits`チェック自体がeventually consistentで、急激なscale-outでは一時的なoverrunもあり得るため、最後に10〜20%程度のsafety factorを設けるのは合理的です。([Karpenter][2])

この構成なら、**AWS/EKS・オンプレ・Karpenterあり/なし・将来Cluster Autoscaler対応**まで同じインターフェースで扱えます。

[1]: https://kubernetes.io/ja/docs/concepts/scheduling-eviction/pod-overhead/?utm_source=chatgpt.com "Podのオーバーヘッド | Kubernetes"
[2]: https://karpenter.sh/docs/concepts/nodepools/?utm_source=chatgpt.com "NodePools | Karpenter"
[3]: https://kubernetes.io/ja/docs/concepts/workloads/pods/init-containers/?utm_source=chatgpt.com "Initコンテナ | Kubernetes"
[4]: https://karpenter.sh/v1.12/concepts/nodeclaims/?utm_source=chatgpt.com "NodeClaims | Karpenter"
