今回は「厳密な capacity planner」ではなく、**Rubyアプリから定期的に取得して `estimated_available_pods` を指標として使う**前提で、実用寄りにまとめます。

Karpenterの現行NodePoolは `spec.limits.cpu/memory` と `status.resources.cpu/memory` を持つので、Nodeを1台ずつ調べて合計するより、**NodePool自身の `spec.limits` と `status.resources` を使う**のがシンプルです。Karpenter公式も `status.resources` を現在のNodePool消費量として案内しています。なお、limitチェック自体はeventually consistentなので、この数字もあくまで推定値です。 ([Karpenter][1])

AWS側は、Service Quotas APIでquota値を取得し、EC2 APIで現在のrunning instanceのvCPUを集計します。EC2のOn-Demand quotaはインスタンスファミリーのカテゴリごとにvCPUで管理されています。 ([AWSドキュメント][2])

---

# 完成形

依存gemはこれです。

```ruby
# Gemfile

gem "kubeclient"
gem "aws-sdk-ec2"
gem "aws-sdk-servicequotas"
```

`kubeclient` はPod内のServiceAccount tokenを使ってKubernetes APIへアクセスできます。現行ドキュメントでは `bearer_token_file` を使う方法が案内されています。 ([RubyDoc][3])

実装は1クラスにまとめます。

```ruby
require "kubeclient"
require "aws-sdk-ec2"
require "aws-sdk-servicequotas"

class EksPodCapacity
  SERVICE_ACCOUNT_TOKEN =
    "/var/run/secrets/kubernetes.io/serviceaccount/token"

  SERVICE_ACCOUNT_CA =
    "/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"

  KARPENTER_API = "https://kubernetes.default.svc/apis/karpenter.sh"

  # EC2 Service Quotas:
  #
  # Running On-Demand Standard (A, C, D, H, I, M, R, T, Z)
  #
  # L-1216C47A is the commonly used quota code.
  #
  # Spotを使う場合などは別quotaなので変更する。
  DEFAULT_QUOTA_CODE = "L-1216C47A"

  CPU_SCALE = 1_000 # millicores / vCPU

  def initialize(
    nodepool_name:,
    subnet_ids:,
    pod_cpu:,
    pod_memory:,
    aws_region: ENV.fetch("AWS_REGION"),
    quota_code: DEFAULT_QUOTA_CODE
  )
    @nodepool_name = nodepool_name
    @subnet_ids = subnet_ids

    @pod_cpu_m = parse_cpu(pod_cpu)
    @pod_memory_bytes = parse_memory(pod_memory)

    raise ArgumentError, "pod_cpu must be > 0" if @pod_cpu_m <= 0
    raise ArgumentError, "pod_memory must be > 0" if @pod_memory_bytes <= 0

    @ec2 = Aws::EC2::Client.new(
      region: aws_region
    )

    @service_quotas = Aws::ServiceQuotas::Client.new(
      region: aws_region
    )

    @nodepool_client = build_nodepool_client
  end

  def estimate
    nodepool = get_nodepool

    nodepool_capacity = calculate_nodepool_capacity(nodepool)
    aws_capacity = calculate_aws_capacity
    subnet_capacity = calculate_subnet_capacity

    candidates = {
      nodepool_cpu: nodepool_capacity[:cpu_pods],
      nodepool_memory: nodepool_capacity[:memory_pods],
      aws_vcpu: aws_capacity[:pods],
      subnet_ip: subnet_capacity[:pods]
    }

    estimated_available_pods = candidates.values.min

    {
      estimated_available_pods: estimated_available_pods,

      limiting_factor: candidates
        .min_by { |_name, value| value }
        .first,

      pod_request: {
        cpu: @pod_cpu_m,
        memory: @pod_memory_bytes
      },

      nodepool: nodepool_capacity,

      aws: aws_capacity,

      subnet: subnet_capacity
    }
  end

  private

  # --------------------------------------------------------------------------
  # Kubernetes / Karpenter
  # --------------------------------------------------------------------------

  def build_nodepool_client
    ssl_options = {}

    if File.exist?(SERVICE_ACCOUNT_CA)
      ssl_options[:ca_file] = SERVICE_ACCOUNT_CA
    end

    auth_options = {
      bearer_token_file: SERVICE_ACCOUNT_TOKEN
    }

    Kubeclient::Client.new(
      KARPENTER_API,
      "v1",
      auth_options: auth_options,
      ssl_options: ssl_options,
      timeouts: {
        open: 5,
        read: 10
      }
    )
  end

  def get_nodepool
    @nodepool_client.get_nodepool(
      @nodepool_name,
      as: :parsed
    )
  end

  def calculate_nodepool_capacity(nodepool)
    spec_limits =
      nodepool.dig("spec", "limits") || {}

    status_resources =
      nodepool.dig("status", "resources") || {}

    limit_cpu = spec_limits["cpu"]
    limit_memory = spec_limits["memory"]

    used_cpu = status_resources["cpu"] || "0"
    used_memory = status_resources["memory"] || "0"

    remaining_cpu_m = if limit_cpu
      [
        parse_cpu(limit_cpu) - parse_cpu(used_cpu),
        0
      ].max
    end

    remaining_memory_bytes = if limit_memory
      [
        parse_memory(limit_memory) - parse_memory(used_memory),
        0
      ].max
    end

    {
      limit_cpu: limit_cpu,
      used_cpu: used_cpu,
      remaining_cpu_m: remaining_cpu_m,
      cpu_pods: remaining_cpu_m ?
        (remaining_cpu_m / @pod_cpu_m) :
        Float::INFINITY,

      limit_memory: limit_memory,
      used_memory: used_memory,
      remaining_memory_bytes: remaining_memory_bytes,
      memory_pods: remaining_memory_bytes ?
        (remaining_memory_bytes / @pod_memory_bytes) :
        Float::INFINITY
    }
  end

  # --------------------------------------------------------------------------
  # AWS Service Quotas / EC2
  # --------------------------------------------------------------------------

  def calculate_aws_capacity
    quota = @service_quotas.get_service_quota(
      service_code: "ec2",
      quota_code: @quota_code
    ).quota

    quota_vcpu = quota.value.to_f

    used_vcpu = running_on_demand_vcpu

    remaining_vcpu = [
      quota_vcpu - used_vcpu,
      0
    ].max

    {
      quota_name: quota.quota_name,
      quota_code: quota.quota_code,

      quota_vcpu: quota_vcpu,
      used_vcpu: used_vcpu,
      remaining_vcpu: remaining_vcpu,

      pods: (
        remaining_vcpu * CPU_SCALE / @pod_cpu_m
      ).floor
    }
  end

  def running_on_demand_vcpu
    total_vcpu = 0

    next_token = nil

    loop do
      response = @ec2.describe_instances(
        filters: [
          {
            name: "instance-state-name",
            values: ["running"]
          }
        ],
        next_token: next_token
      )

      instance_ids = []

      response.reservations.each do |reservation|
        reservation.instances.each do |instance|
          # lifecycle が "spot" のものは除外。
          #
          # nil = On-Demand
          # "spot" = Spot
          #
          # このクラスではOn-Demand quotaを対象にしている。
          next if instance.instance_lifecycle == "spot"

          instance_ids << instance.instance_id
        end
      end

      unless instance_ids.empty?
        types = @ec2.describe_instance_types(
          instance_type_names: (
            response.reservations
              .flat_map(&:instances)
              .select { |i| instance_ids.include?(i.instance_id) }
              .map(&:instance_type)
              .uniq
          )
        )

        vcpu_by_type = {}

        types.instance_types.each do |type|
          vcpu_by_type[type.instance_type] =
            type.v_cpu_info.default_v_cpus
        end

        response.reservations.each do |reservation|
          reservation.instances.each do |instance|
            next if instance.instance_lifecycle == "spot"

            vcpu = vcpu_by_type[instance.instance_type]

            total_vcpu += vcpu if vcpu
          end
        end
      end

      next_token = response.next_token

      break if next_token.nil?
    end

    total_vcpu
  end

  # --------------------------------------------------------------------------
  # Subnet
  # --------------------------------------------------------------------------

  def calculate_subnet_capacity
    return {
      subnet_count: 0,
      available_ips: Float::INFINITY,
      pods: Float::INFINITY
    } if @subnet_ids.empty?

    response = @ec2.describe_subnets(
      subnet_ids: @subnet_ids
    )

    available_ips =
      response.subnets.sum do |subnet|
        subnet.available_ip_address_count || 0
      end

    {
      subnet_count: response.subnets.length,
      available_ips: available_ips,

      # 指標としては 1 available IP = 1 Pod とみなす。
      #
      # 実際には AWS VPC CNI の ENI / prefix delegation /
      # warm IP 設定などがあるため厳密ではない。
      pods: available_ips
    }
  end

  # --------------------------------------------------------------------------
  # Kubernetes resource quantity parser
  # --------------------------------------------------------------------------

  def parse_cpu(value)
    value = value.to_s.strip

    case value
    when /\An([\d.]+)\z/
      # nano CPU -> millicores
      Regexp.last_match(1).to_f / 1_000_000.0

    when /\Au([\d.]+)\z/
      # micro CPU -> millicores
      Regexp.last_match(1).to_f / 1_000.0

    when /\Am([\d.]+)\z/
      # milli CPU
      Regexp.last_match(1).to_f

    else
      # plain CPU is in cores
      value.to_f * CPU_SCALE
    end
  end

  def parse_memory(value)
    value = value.to_s.strip

    binary_units = {
      "Ki" => 1024,
      "Mi" => 1024**2,
      "Gi" => 1024**3,
      "Ti" => 1024**4,
      "Pi" => 1024**5,
      "Ei" => 1024**6
    }

    binary_units.each do |suffix, multiplier|
      if value.end_with?(suffix)
        number = value.delete_suffix(suffix).to_f
        return (number * multiplier).to_i
      end
    end

    decimal_units = {
      "K" => 1_000,
      "M" => 1_000**2,
      "G" => 1_000**3,
      "T" => 1_000**4,
      "P" => 1_000**5,
      "E" => 1_000**6
    }

    decimal_units.each do |suffix, multiplier|
      if value.end_with?(suffix)
        number = value.delete_suffix(suffix).to_f
        return (number * multiplier).to_i
      end
    end

    value.to_i
  end
end
```

ただし、上のコードには1点、初期化漏れがあります。`@quota_code` を設定する必要があります。

```ruby
@quota_code = quota_code
```

を `initialize` に追加してください。

---

# 使用例

例えば、Podのrequestが、

```yaml
resources:
  requests:
    cpu: 500m
    memory: 1Gi
```

なら、

```ruby
capacity = EksPodCapacity.new(
  nodepool_name: "default",
  subnet_ids: [
    "subnet-0123456789abcdef0",
    "subnet-0123456789abcdef1",
    "subnet-0123456789abcdef2"
  ],
  pod_cpu: "500m",
  pod_memory: "1Gi"
)

pp capacity.estimate
```

例えばこんな結果になります。

```ruby
{
  estimated_available_pods: 360,

  limiting_factor: "aws_vcpu",

  pod_request: {
    cpu: 500.0,
    memory: 1073741824
  },

  nodepool: {
    limit_cpu: "500",
    used_cpu: "320",
    remaining_cpu_m: 180000.0,
    cpu_pods: 360,

    limit_memory: "2Ti",
    used_memory: "1Ti",
    remaining_memory_bytes: 1099511627776,
    memory_pods: 1024
  },

  aws: {
    quota_name: "Running On-Demand Standard ...",
    quota_code: "L-1216C47A",
    quota_vcpu: 500.0,
    used_vcpu: 320,
    remaining_vcpu: 180,
    pods: 360
  },

  subnet: {
    subnet_count: 3,
    available_ips: 812,
    pods: 812
  }
}
```

つまり、

```text
NodePool CPU      360 Pod
NodePool Memory  1024 Pod
AWS vCPU          360 Pod
Subnet IP         812 Pod
-------------------------
推定              360 Pod
```

という見方です。

---

# ただし、AWS vCPUの部分は少し重要

ここは今回の実装で一番注意したいところです。

AWSのOn-Demand quotaは**1つではありません**。

例えば、

* Standard
* DL
* F
* G/VT
* HPC
* High Memory
* Inf
* P
* Trn
* X

などに分かれています。AWS公式にもそれぞれ別のvCPU quotaとして記載されています。 ([AWSドキュメント][2])

なので、

```ruby
quota_code: "L-1216C47A"
```

は、

> **KarpenterがStandard系EC2をOn-Demandで起動する**

という前提です。

例えばNodePoolが、

```yaml
requirements:
  - key: karpenter.sh/capacity-type
    operator: In
    values:
      - spot
```

なら、Spot用quotaを見る必要があります。

---

# Spotの場合

この場合は例えば、

```ruby
capacity = EksPodCapacity.new(
  nodepool_name: "spot",
  subnet_ids: subnet_ids,
  pod_cpu: "500m",
  pod_memory: "1Gi",
  quota_code: "SPOT_QUOTA_CODE"
)
```

のようにします。

そして現在使用中のEC2についても、

```ruby
instance.instance_lifecycle == "spot"
```

を集計対象にする必要があります。

なので、実際にはこのクラスをもう一段一般化して、

```ruby
capacity_type: :on_demand
```

または

```ruby
capacity_type: :spot
```

を指定する設計にしてもいいです。

---

# もう一つ重要なのがSubnet IP

`DescribeSubnets` の `available_ip_address_count` は、AWS SDKでも「そのsubnetで未使用のprivate IPv4 address数」と定義されています。 ([AWSドキュメント][4])

したがって、

```ruby
available_ips = 800
```

なら、

```text
Subnet capacity ≒ 800 Pod
```

という指標にはできます。

ただし、これは**「800 Podを必ず追加できる」ではありません**。

AWS VPC CNIでは、

```text
Pod
 ↓
ENI / secondary IP
または
prefix delegation
 ↓
Subnet IP
```

なので、

* ENIの上限
* instanceごとのENI/IP上限
* prefix delegation
* `WARM_IP_TARGET`
* `WARM_PREFIX_TARGET`
* `MINIMUM_IP_TARGET`

などが絡みます。

したがって今回の目的なら、

```ruby
subnet_available_ips
```

を**「network capacityの参考値」**として扱うのがちょうどいいです。

---

# IAM / Kubernetes RBAC

このRubyアプリをEKSのPodとして動かすなら、少なくとも以下が必要です。

### Kubernetes RBAC

NodePoolはcluster-scopedなので、

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: capacity-reader
  namespace: your-app
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: capacity-reader
rules:
  - apiGroups:
      - karpenter.sh
    resources:
      - nodepools
    verbs:
      - get
      - list
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: capacity-reader
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: capacity-reader
subjects:
  - kind: ServiceAccount
    name: capacity-reader
    namespace: your-app
```

これで、

```ruby
get_nodepool(...)
```

ができます。

---

# AWS IAM

AWS側は概ね、

```text
servicequotas:GetServiceQuota
ec2:DescribeInstances
ec2:DescribeInstanceTypes
ec2:DescribeSubnets
```

だけです。

例えばIAM policyは、

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "servicequotas:GetServiceQuota",
        "ec2:DescribeInstances",
        "ec2:DescribeInstanceTypes",
        "ec2:DescribeSubnets"
      ],
      "Resource": "*"
    }
  ]
}
```

で足ります。

EKS Pod Identity / IRSAでこのIAM RoleをPodに割り当てれば、AWS SDK側でアクセスキーをコードに書く必要はありません。

---

# そして、僕なら実際には `estimate` をこう使う

Railsなどなら、毎リクエストAWS APIを叩くのは避けます。

例えば、

```ruby
class CapacityService
  CACHE_TTL = 30.seconds

  def self.current
    Rails.cache.fetch(
      "eks-pod-capacity:v1",
      expires_in: CACHE_TTL
    ) do
      EksPodCapacity.new(
        nodepool_name: "default",
        subnet_ids: ENV.fetch("EKS_POD_SUBNET_IDS").split(","),
        pod_cpu: "500m",
        pod_memory: "1Gi"
      ).estimate
    end
  end
end
```

そして、

```ruby
capacity = CapacityService.current

if capacity[:estimated_available_pods] < 100
  # capacity low
end
```

くらいにします。

**30秒程度のstalenessはこの用途なら全く問題ない**と思います。

---

## さらに改善するなら

実はこの用途なら、僕は最終的に

```text
NodePool limit
      ↓
NodePool status.resources
      ↓
┌─────────────────────────────┐
│                             │
│  CPU remaining → Pod換算    │
│  MEM remaining → Pod換算    │
│                             │
└─────────────────────────────┘
      ↓
AWS quota remaining → Pod換算
      ↓
Subnet available IP → Pod換算
      ↓
        min()
      ↓
estimated_available_pods
```

という構造にします。

そして**「現在のNode allocatableを全Nodeから集計する処理」は入れない**です。

理由は、KarpenterがNodePoolの現在消費量を `status.resources` として持っているからです。公式ドキュメントでも、`status.resources.cpu/memory` を現在のNodePoolリソースとして確認できるようになっています。 ([Karpenter][5])

また、AWS Service Quotas API自体は `get_service_quota` で適用済みquotaを取得できます。 ([AWSドキュメント][6])

**この用途では「NodePool / AWS / subnet の各制約を同じPod request単位に正規化して、一番小さい値を出す」という設計がかなり扱いやすいです。**

なお、上のAWS実装は「現在runningのOn-Demand EC2をvCPU集計」する簡易版なので、**Capacity Reservationなどquotaにカウントされるものまで完全には反映しません**。したがって、まさに今回の「指標程度」という用途に合わせた実装です。

[1]: https://karpenter.sh/v1.12/concepts/nodepools/?utm_source=chatgpt.com "NodePools | Karpenter"
[2]: https://docs.aws.amazon.com/ec2/latest/instancetypes/ec2-instance-quotas.html?utm_source=chatgpt.com "Amazon EC2 instance type quotas - Amazon EC2"
[3]: https://www.rubydoc.info/gems/kubeclient/4.13.0?utm_source=chatgpt.com "RubyDoc.info: File: README – Documentation for kubeclient (4.13.0) – RubyDoc.info"
[4]: https://docs.aws.amazon.com/sdk-for-ruby/v3/api/Aws/EC2/Types/Subnet.html?utm_source=chatgpt.com "Class: Aws::EC2::Types::Subnet — AWS SDK for Ruby V3"
[5]: https://karpenter.sh/docs/concepts/nodepools/?utm_source=chatgpt.com "NodePools | Karpenter"
[6]: https://docs.aws.amazon.com/sdk-for-ruby/v3/api/Aws/ServiceQuotas/Client.html?utm_source=chatgpt.com "Class: Aws::ServiceQuotas::Client — AWS SDK for Ruby V3"

