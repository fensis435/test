**「厳密な残りPod数」ではなく、Rubyアプリから見える範囲で `このくらい余裕がある` を出す**なら、かなりシンプルにできます。

実運用では、次の4つを集めて `min()` を取るくらいが扱いやすいです。

```text
推定残りPod数 =
  min(
    NodePoolのCPU上限から見た残り,
    NodePoolのMemory上限から見た残り,
    AWS vCPU quotaから見た残り,
    現在のNodeの空きcapacity + これから増やせるcapacity
  )
```

ただし、最後の「これから増やせるcapacity」は厳密にやるとKarpenterのinstance selectionまで再現する必要があるので、**指標としてはNodePool limitsとAWS quotaを主軸にする**のがおすすめです。

以下のような実装にできます。

---

## Ruby実装例

Kubernetes APIには [`kubeclient`](https://github.com/fabric8io/kubernetes-client-ruby) を使う想定です。

```ruby
require "kubeclient"

class EKSCapacity
  POD_CPU_MILLI = 500
  POD_MEMORY_BYTES = 1 * 1024 * 1024 * 1024 # 1 Gi

  def initialize
    config = Kubeclient::Config.read(
      Kubeclient::Config::KubeConfig::ENV_VAR
    )

    @client = Kubeclient::Client.new(
      config.context.api_endpoint,
      "v1",
      ssl_options: config.context.ssl_options,
      auth_options: config.context.auth_options
    )

    @custom_client = Kubeclient::Client.new(
      config.context.api_endpoint,
      "v1",
      ssl_options: config.context.ssl_options,
      auth_options: config.context.auth_options
    )
  end

  def capacity
    {
      current: current_capacity,
      nodepool: nodepool_capacity,
      aws: aws_capacity
    }
  end

  private

  # 現在Nodeに乗っているPodを考慮したcapacity
  def current_capacity
    nodes = @client.get_nodes

    cpu = 0
    memory = 0
    pods = 0

    nodes.each do |node|
      allocatable = node.status.allocatable

      cpu_capacity = parse_cpu(allocatable["cpu"])
      memory_capacity = parse_memory(allocatable["memory"])

      used_cpu = 0
      used_memory = 0

      pods_for_node = @client.get_pods(
        field_selector: "spec.nodeName=#{node.metadata.name}"
      )

      pods_for_node.each do |pod|
        next if %w[Succeeded Failed].include?(pod.status.phase)

        pod.spec.containers.each do |container|
          requests = container.resources&.requests || {}

          used_cpu += parse_cpu(requests["cpu"] || "0")
          used_memory += parse_memory(requests["memory"] || "0")
        end
      end

      cpu += [cpu_capacity - used_cpu, 0].max
      memory += [memory_capacity - used_memory, 0].max

      pods += [
        parse_integer(allocatable["pods"]) -
          pods_for_node.count { |p| !%w[Succeeded Failed].include?(p.status.phase) },
        0
      ].max
    end

    {
      cpu_pods: cpu / POD_CPU_MILLI,
      memory_pods: memory / POD_MEMORY_BYTES,
      pod_count: pods
    }
  end

  # NodePoolのlimitを見る
  #
  # 実際にはNodePool CRDを取得する。
  #
  # ここでは例として:
  #
  # limits:
  #   cpu: 100
  #   memory: 400Gi
  #
  def nodepool_capacity
    limits = {
      "cpu" => "100",
      "memory" => "400Gi"
    }

    {
      cpu_pods: parse_cpu(limits["cpu"]) / POD_CPU_MILLI,
      memory_pods: parse_memory(limits["memory"]) / POD_MEMORY_BYTES
    }
  end

  # AWS quotaについてはAWS SDKから取得する。
  #
  # ここでは例としてquota 500 vCPU、
  # 現在250 vCPU使用済みとする。
  def aws_capacity
    quota = 500
    used = current_ec2_vcpu

    remaining = [quota - used, 0].max

    {
      vcpu_remaining: remaining,
      pod_count: (remaining * 1000) / POD_CPU_MILLI
    }
  end

  def current_ec2_vcpu
    # AWS SDKで取得する実装に置き換える。
    250
  end

  def parse_cpu(value)
    return 0 if value.nil?

    value = value.to_s

    if value.end_with?("m")
      value.delete_suffix("m").to_i
    else
      value.to_f * 1000
    end
  end

  def parse_memory(value)
    return 0 if value.nil?

    value = value.to_s

    units = {
      "Ki" => 1024,
      "Mi" => 1024**2,
      "Gi" => 1024**3,
      "Ti" => 1024**4
    }

    units.each do |suffix, multiplier|
      if value.end_with?(suffix)
        return value.delete_suffix(suffix).to_f * multiplier
      end
    end

    value.to_i
  end

  def parse_integer(value)
    value.to_i
  end
end
```

ただ、実際にはこれをもう少し整理したほうがいいです。

---

# 僕ならこうする

今回の目的なら、**「現在空いているcapacity」と「Karpenterが追加できそうなcapacity」を分離**します。

例えばRuby側で、

```ruby
capacity = {
  cpu: {
    current_free: 120_000, # 120 vCPU
    estimated_max: 500_000 # 500 vCPU
  },
  memory: {
    current_free: 300.gigabytes,
    estimated_max: 2.terabytes
  },
  pods: {
    current_free: 250,
    estimated_max: 1_000
  }
}
```

として、

```ruby
estimated_pods = [
  capacity[:cpu][:estimated_max] / pod_cpu,
  capacity[:memory][:estimated_max] / pod_memory,
  capacity[:pods][:estimated_max]
].min
```

くらいにします。

---

# NodePool limitsは「追加可能量」として扱う

ここが結構重要です。

例えばNodePoolが、

```yaml
limits:
  cpu: "500"
  memory: "2Ti"
```

で、現在すでに、

```text
NodePool内のNode
CPU = 300 vCPU
MEM = 1Ti
```

使っているなら、

```text
CPU remaining = 200 vCPU
MEM remaining = 1Ti
```

です。

Podが、

```text
500m CPU
1Gi memory
```

なら、

```text
CPU → 200 / 0.5 = 400 Pod
MEM → 1024 / 1 = 1024 Pod
```

なので、

```text
NodePool capacity ≒ 400 Pod
```

と見る。

---

# AWS quotaも同じ

例えばEC2 quotaが、

```text
500 vCPU
```

現在EC2が、

```text
320 vCPU
```

なら、

```text
remaining = 180 vCPU
```

Podが500mなら、

```text
180 / 0.5
= 360 Pod
```

です。

すると、

```text
NodePool → 400 Pod
AWS      → 360 Pod
```

なので、

```text
estimated additional pods = 360
```

とする。

---

# Rubyでは最終的にこれだけでも結構使える

例えば、

```ruby
class CapacityEstimator
  def initialize(
    pod_cpu_millicores:,
    pod_memory_bytes:,
    nodepool_cpu_millicores:,
    nodepool_memory_bytes:,
    nodepool_used_cpu_millicores:,
    nodepool_used_memory_bytes:,
    aws_vcpu_quota:,
    aws_vcpu_used:
  )
    @pod_cpu = pod_cpu_millicores
    @pod_memory = pod_memory_bytes

    @nodepool_cpu = nodepool_cpu_millicores
    @nodepool_memory = nodepool_memory_bytes

    @nodepool_used_cpu = nodepool_used_cpu_millicores
    @nodepool_used_memory = nodepool_used_memory_bytes

    @aws_vcpu_quota = aws_vcpu_quota
    @aws_vcpu_used = aws_vcpu_used
  end

  def estimate
    [
      nodepool_cpu_capacity,
      nodepool_memory_capacity,
      aws_cpu_capacity
    ].min
  end

  def details
    {
      nodepool_cpu: nodepool_cpu_capacity,
      nodepool_memory: nodepool_memory_capacity,
      aws_cpu: aws_cpu_capacity,
      estimated_pods: estimate
    }
  end

  private

  def nodepool_cpu_capacity
    remaining =
      @nodepool_cpu - @nodepool_used_cpu

    remaining / @pod_cpu
  end

  def nodepool_memory_capacity
    remaining =
      @nodepool_memory - @nodepool_used_memory

    remaining / @pod_memory
  end

  def aws_cpu_capacity
    remaining_vcpu =
      @aws_vcpu_quota - @aws_vcpu_used

    (remaining_vcpu * 1000) / @pod_cpu
  end
end
```

例えば、

```ruby
estimator = CapacityEstimator.new(
  pod_cpu_millicores: 500,
  pod_memory_bytes: 1.gigabyte,

  nodepool_cpu_millicores: 500_000,
  nodepool_memory_bytes: 2.terabytes,

  nodepool_used_cpu_millicores: 300_000,
  nodepool_used_memory_bytes: 1.terabytes,

  aws_vcpu_quota: 500,
  aws_vcpu_used: 320
)

pp estimator.details
```

結果は概念的に、

```ruby
{
  nodepool_cpu:    400,
  nodepool_memory: 1024,
  aws_cpu:         360,
  estimated_pods:  360
}
```

となります。

つまり、

> **「このPod specなら、現在のクラスタ状態からあと約360個くらいは起動できそう」**

という指標にできます。

---

## さらにVPC IPを加える

ここも同じ考え方です。

```ruby
def subnet_ip_capacity(available_ips)
  available_ips
end
```

として、

```ruby
[
  nodepool_cpu_capacity,
  nodepool_memory_capacity,
  aws_cpu_capacity,
  subnet_available_ips
].min
```

とすればいいです。

ただし、**subnetの空きIPをそのままPod数とみなすのはAWS VPC CNIの設定によって誤差が出る**ので、これは「参考値」と明示するのがいいです。

---

# 実際に欲しいなら、次の形がかなりおすすめ

Rubyアプリから、

```ruby
capacity = eks_capacity.estimate(
  pod_cpu: "500m",
  pod_memory: "1Gi"
)
```

すると、

```ruby
{
  estimated_available_pods: 360,

  constraints: {
    nodepool_cpu: 400,
    nodepool_memory: 1024,
    aws_vcpu: 360,
    subnet_ip: 700
  }
}
```

を返す。

さらに、

```ruby
capacity[:estimated_available_pods] < 100
```

なら「capacity low」と判断する。

**「360」という数字そのものを正確な保証値として使わず、オートスケールやジョブ投入の判断材料にする**なら、このくらいの粗さがちょうどいいと思います。

なお、実装上は **NodePoolの `limits` をKubernetes APIから取得する部分**と、**AWS Service Quotas / EC2からvCPU使用量・Subnetのavailable IPを取得する部分**を足せば、かなり実用的なRubyクラスにできます。必要ならそこまで含めた実コードにできます。
