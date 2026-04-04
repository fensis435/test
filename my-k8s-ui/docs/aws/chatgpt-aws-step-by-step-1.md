# 🎯 全体方針（重要）

* **各Stepごとにスタック分割**
* **deployで統一**
* **削除は逆順**

---

# 🧱 Step1：IAM + EKS + NodeGroup

---

## 📄 CFnテンプレ（step1.yaml）

```yaml
AWSTemplateFormatVersion: '2010-09-09'

Parameters:
  ClusterName:
    Type: String
  SubnetIds:
    Type: List<AWS::EC2::Subnet::Id>

Resources:

  # EKS Cluster Role
  EKSClusterRole:
    Type: AWS::IAM::Role
    Properties:
      AssumeRolePolicyDocument:
        Statement:
          - Effect: Allow
            Principal:
              Service: eks.amazonaws.com
            Action: sts:AssumeRole
      ManagedPolicyArns:
        - arn:aws:iam::aws:policy/AmazonEKSClusterPolicy

  # Node Role
  NodeRole:
    Type: AWS::IAM::Role
    Properties:
      AssumeRolePolicyDocument:
        Statement:
          - Effect: Allow
            Principal:
              Service: ec2.amazonaws.com
            Action: sts:AssumeRole
      ManagedPolicyArns:
        - arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy
        - arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly
        - arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy

  Cluster:
    Type: AWS::EKS::Cluster
    Properties:
      Name: !Ref ClusterName
      RoleArn: !GetAtt EKSClusterRole.Arn
      ResourcesVpcConfig:
        SubnetIds: !Ref SubnetIds

  NodeGroup:
    Type: AWS::EKS::Nodegroup
    Properties:
      ClusterName: !Ref ClusterName
      NodeRole: !GetAtt NodeRole.Arn
      Subnets: !Ref SubnetIds
      ScalingConfig:
        DesiredSize: 2
        MinSize: 1
        MaxSize: 3
```

---

## ▶️ 実行

```bash
aws cloudformation deploy \
  --stack-name step1-eks \
  --template-file step1.yaml \
  --parameter-overrides \
    ClusterName=my-eks \
    SubnetIds=subnet-xxx,subnet-yyy \
  --capabilities CAPABILITY_NAMED_IAM
```

---

## 🔍 確認

```bash
aws eks describe-cluster --name my-eks
```

```bash
aws eks list-nodegroups --cluster-name my-eks
```

---

## 🗑 削除

```bash
aws cloudformation delete-stack --stack-name step1-eks
```

---

# ☸️ Step2：kubectl接続 + Pod確認

---

## kubeconfig設定

```bash
aws eks update-kubeconfig --name my-eks
```

---

## Pod

```bash
kubectl run nginx --image=nginx
kubectl get pods
```

---

## 削除

```bash
kubectl delete pod nginx
```

---

# ⚡ Step3：Karpenter

---

👉 Karpenter

---

## ※CFnではなくHelm

```bash
helm repo add karpenter https://charts.karpenter.sh
helm install karpenter karpenter/karpenter
```

---

## 確認

```bash
kubectl get pods -n karpenter
```

---

## 削除

```bash
helm uninstall karpenter
```

---

# 🌐 Step4：ALB + Ingress

---

## 前提

👉 AWS Load Balancer Controller

---

## インストール

```bash
helm install aws-load-balancer-controller \
  eks/aws-load-balancer-controller
```

---

## Ingress例

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: sample
  annotations:
    alb.ingress.kubernetes.io/scheme: internal
spec:
  rules:
    - http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: nginx
                port:
                  number: 80
```

---

## 確認

```bash
kubectl get ingress
```

---

## 削除

```bash
kubectl delete ingress sample
helm uninstall aws-load-balancer-controller
```

---

# 🌍 Step5：DNS（Private Hosted Zone）

---

👉 Amazon Route 53

---

## 📄 CFn（step5.yaml）

```yaml
Parameters:
  VpcId:
    Type: String
  DomainName:
    Type: String

Resources:
  HostedZone:
    Type: AWS::Route53::HostedZone
    Properties:
      Name: !Ref DomainName
      VPCs:
        - VPCId: !Ref VpcId
          VPCRegion: ap-northeast-1
```

---

## ▶️ 実行

```bash
aws cloudformation deploy \
  --stack-name step5-dns \
  --template-file step5.yaml \
  --parameter-overrides \
    VpcId=vpc-xxxx \
    DomainName=dev.internal.example.com
```

---

## 🔍 確認

```bash
aws route53 list-hosted-zones
```

---

## 🗑 削除

```bash
aws cloudformation delete-stack --stack-name step5-dns
```

---

# 🔁 毎日の開発フロー（超重要）

---

## 起動

```bash
step1 → step2 → (step3,4,5 必要なら)
```

---

## 終了時

```bash
kubectl delete all --all
helm uninstall ...
aws cloudformation delete-stack step5-dns
aws cloudformation delete-stack step1-eks
```

---

# 🎯 まとめ（実務最適）

---

## 最低限回すなら

👉 Step1 + Step2だけでOK

---

## 徐々に追加

* Step3：スケール
* Step4：外部公開
* Step5：ドメイン

---

# 💬 最後に

この構成なら👇

* 毎日作って
* 毎日壊して
* 毎日検証できる
