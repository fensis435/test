いい質問。ここが **「EKSを作っただけ」から「本番で金を無駄にしない」**に変わる分岐点です。
しかも **Proxy前提**だと、Karpenterは「考え方」を外すと一生動きません。

なので今回は👇の順でいきます。

---

# 今日のゴール（Karpenter編）

> * 管理Nodeは常駐
> * **重いPodが来た瞬間だけ** EC2が生える
> * ジョブが終わったら **勝手に消える**
> * 外向き通信は **VPC Endpoint + Proxyのみ**

---

# まず結論：Karpenterは何を見てスケールする？

Auto Scaling Group と違って、Karpenterはこれ👇だけを見ます。

> **「スケジューリングできない Pod が存在するか？」**

つまり：

1. Podが作られる
2. CPU / Memory / GPU が足りない
3. Kubernetes Scheduler が「置けない」と判断
4. **Karpenterが EC2 を1台作る**
5. Podがそこに乗る
6. Podが消えたら Node も消える

👉 **負荷ではなく Pod がトリガー**

---

# Proxy前提での全体構成（重要）

```
[Pod作成]
   ↓
[Scheduler: 置けない]
   ↓
[Karpenter]
   ↓
[EC2 API] ← VPC Endpoint
   ↓
[Node起動]
   ↓
[ECR Pull] ← VPC Endpoint
   ↓
[実行]
```

❌ NAT不要
❌ インターネット直行なし
⭕ Proxyは「例外通信用」にのみ使う

---

# ステップ① KarpenterがAWS操作できるようにする

## IAM Role（必須）

```hcl
resource "aws_iam_role" "karpenter" {
  name = "karpenter-controller"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.eks.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
    }]
  })
}
```

### なぜ必要？

* Karpenterは **Pod**
* EC2を作るには **IAM権限**
* → IRSA（ServiceAccount + Role）

---

# ステップ② Karpenter Controller を Proxy 前提で起動

### values.yaml（超重要）

```yaml
controller:
  env:
    - name: HTTP_PROXY
      value: http://proxy.corp.local:8080
    - name: HTTPS_PROXY
      value: http://proxy.corp.local:8080
    - name: NO_PROXY
      value: 169.254.169.254,localhost,127.0.0.1,.cluster.local,.amazonaws.com
```

👉 これがないと

* STS
* EC2
* Pricing API

で **無言で死にます**

---

# ステップ③ NodePool（= どういうEC2を作るか）

ここが **スケールの本体**。

```yaml
apiVersion: karpenter.sh/v1beta1
kind: NodePool
metadata:
  name: compute
spec:
  limits:
    cpu: "1000"
  template:
    spec:
      nodeClassRef:
        name: compute-class
      requirements:
        - key: kubernetes.io/arch
          operator: In
          values: ["amd64"]
        - key: node.kubernetes.io/instance-type
          operator: In
          values: ["c6i.large", "c6i.xlarge"]
      taints:
        - key: workload
          value: compute
          effect: NoSchedule
```

### 何をしている？

* 「計算用Nodeはこの条件で作れ」
* 普段は **0台**
* 必要になったら **無制限に増える（上限あり）**

---

# ステップ④ EC2NodeClass（Proxy前提AMI設定）

```yaml
apiVersion: karpenter.k8s.aws/v1beta1
kind: EC2NodeClass
metadata:
  name: compute-class
spec:
  amiFamily: AL2
  subnetSelectorTerms:
    - tags:
        karpenter.sh/discovery: proxy-eks
  securityGroupSelectorTerms:
    - tags:
        karpenter.sh/discovery: proxy-eks
  role: eks-node-role
  userData: |
    #!/bin/bash
    echo "HTTP_PROXY=http://proxy.corp.local:8080" >> /etc/environment
    echo "HTTPS_PROXY=http://proxy.corp.local:8080" >> /etc/environment
    echo "NO_PROXY=169.254.169.254,.cluster.local,.amazonaws.com" >> /etc/environment
```

👉 **Node自身も Proxy を知っている必要がある**

---

# ステップ⑤ Pod側（ここが一番わかりやすい）

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: heavy-job
spec:
  template:
    spec:
      tolerations:
        - key: "workload"
          operator: "Equal"
          value: "compute"
          effect: "NoSchedule"
      containers:
        - name: worker
          image: 123456789012.dkr.ecr.ap-northeast-1.amazonaws.com/heavy:latest
          resources:
            requests:
              cpu: "8"
              memory: "32Gi"
      restartPolicy: Never
```

### ここで何が起きる？

* 管理Node：CPU足りない → 置けない
* Karpenter：「じゃあ c6i.xlarge 作るわ」
* EC2起動
* Pod実行
* Job完了
* Node削除

🎉 **完全自動**

---

# Proxy前提で「よく死ぬポイント」⚠️

| 症状           | 原因                  |
| ------------ | ------------------- |
| Node作られない    | STS Endpoint なし     |
| Node起動で止まる   | Proxy設定がAMIにない      |
| Image Pull失敗 | ECR Endpoint不足      |
| Pricingエラー   | Proxy or NO_PROXY漏れ |

👉 **95%は Endpoint or NO_PROXY**

---

# まとめ

> Karpenterはスケジューリング不能なPodのみを契機にEC2を動的生成し、
> ジョブ終了後は即時削除されるため、計算資源の常時確保を行いません。
> AWS API通信はVPC Endpointを利用し、例外通信のみProxy経由で制御しています。

---

