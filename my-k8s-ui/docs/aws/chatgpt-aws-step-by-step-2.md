---

# 🎯 前提（Pod Identity版）

* クラスタは Amazon EKS
* Pod Identity Agentが有効（通常は自動）
* OIDC不要
* IAM Roleは `pods.eks.amazonaws.com`
* associationで紐付け

---

# ⚡ Step3：Karpenter（Pod Identity版）

👉 Karpenter

---

# 🧱 Step3-1：CFn（IAM Role）

## 📄 step3-karpenter-iam.yaml

```yaml
AWSTemplateFormatVersion: '2010-09-09'

Parameters:
  ClusterName:
    Type: String

Resources:

  KarpenterRole:
    Type: AWS::IAM::Role
    Properties:
      RoleName: !Sub "${ClusterName}-karpenter-role"
      AssumeRolePolicyDocument:
        Statement:
          - Effect: Allow
            Principal:
              Service: pods.eks.amazonaws.com
            Action: sts:AssumeRole
      Policies:
        - PolicyName: karpenter
          PolicyDocument:
            Statement:
              - Effect: Allow
                Action:
                  - ec2:RunInstances
                  - ec2:TerminateInstances
                  - ec2:Describe*
                Resource: "*"
```

---

## ▶️ 実行

```bash
aws cloudformation deploy \
  --stack-name step3-karpenter-iam \
  --template-file step3-karpenter-iam.yaml \
  --parameter-overrides ClusterName=my-eks \
  --capabilities CAPABILITY_NAMED_IAM
```

---

# 🧩 Step3-2：Pod Identity Association

```bash
aws eks create-pod-identity-association \
  --cluster-name my-eks \
  --namespace karpenter \
  --service-account karpenter \
  --role-arn arn:aws:iam::xxx:role/my-eks-karpenter-role
```

---

# 🧩 Step3-3：Karpenterインストール

```bash
helm repo add karpenter https://charts.karpenter.sh

helm install karpenter karpenter/karpenter \
  --namespace karpenter --create-namespace
```

---

# 🧩 Step3-4：NodePool

```yaml
apiVersion: karpenter.sh/v1beta1
kind: NodePool
metadata:
  name: default
spec:
  template:
    spec:
      requirements:
        - key: "node.kubernetes.io/instance-type"
          operator: In
          values: ["t3.medium"]
```

---

## 🔍 確認

```bash
kubectl get pods -n karpenter
kubectl get nodes
```

---

## 🗑 削除

```bash
helm uninstall karpenter -n karpenter

aws eks list-pod-identity-associations --cluster-name my-eks

aws eks delete-pod-identity-association \
  --cluster-name my-eks \
  --association-id xxx

aws cloudformation delete-stack \
  --stack-name step3-karpenter-iam
```

---

# 🌐 Step4：ALB Controller（Pod Identity版）

👉 AWS Load Balancer Controller

---

# 🧱 Step4-1：CFn（IAM Role）

## 📄 step4-alb-iam.yaml

```yaml
AWSTemplateFormatVersion: '2010-09-09'

Resources:

  ALBRole:
    Type: AWS::IAM::Role
    Properties:
      RoleName: my-eks-alb-role
      AssumeRolePolicyDocument:
        Statement:
          - Effect: Allow
            Principal:
              Service: pods.eks.amazonaws.com
            Action: sts:AssumeRole
      ManagedPolicyArns:
        - arn:aws:iam::aws:policy/ElasticLoadBalancingFullAccess
```

---

## ▶️ 実行

```bash
aws cloudformation deploy \
  --stack-name step4-alb-iam \
  --template-file step4-alb-iam.yaml \
  --capabilities CAPABILITY_NAMED_IAM
```

---

# 🧩 Step4-2：Pod Identity Association

```bash
aws eks create-pod-identity-association \
  --cluster-name my-eks \
  --namespace kube-system \
  --service-account aws-load-balancer-controller \
  --role-arn arn:aws:iam::xxx:role/my-eks-alb-role
```

---

# 🧩 Step4-3：Controllerインストール

```bash
helm repo add eks https://aws.github.io/eks-charts

helm install aws-load-balancer-controller \
  eks/aws-load-balancer-controller \
  -n kube-system
```

---

# 🧩 Step4-4：Ingress（internal ALB）

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: internal-alb
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

## 🔍 確認

```bash
kubectl get ingress
aws elbv2 describe-load-balancers
```

---

## 🗑 削除

```bash
kubectl delete ingress internal-alb

helm uninstall aws-load-balancer-controller -n kube-system

aws eks delete-pod-identity-association \
  --cluster-name my-eks \
  --association-id xxx

aws cloudformation delete-stack \
  --stack-name step4-alb-iam
```

---

# 🌍 Step5：Private DNS（Route53）

👉 Amazon Route 53

---

# 🧱 Step5-1：Hosted Zone

## 📄 step5-dns.yaml

```yaml
AWSTemplateFormatVersion: '2010-09-09'

Parameters:
  VpcId:
    Type: String
  DomainName:
    Type: String

Resources:
  PrivateZone:
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
  --template-file step5-dns.yaml \
  --parameter-overrides \
    VpcId=vpc-xxxx \
    DomainName=dev.internal.example.com
```

---

# 🧩 Step5-2：Record（ALBに紐付け）

※ALBのDNSは手動確認 or 自動取得

```bash
aws elbv2 describe-load-balancers
```

---

```yaml
Record:
  Type: AWS::Route53::RecordSet
  Properties:
    HostedZoneName: dev.internal.example.com.
    Name: app.dev.internal.example.com
    Type: A
    AliasTarget:
      DNSName: internal-xxxx.elb.amazonaws.com
      HostedZoneId: ZXXXXXXXX
```

---

## 🔍 確認

```bash
aws route53 list-hosted-zones
aws route53 list-resource-record-sets --hosted-zone-id ZXXX
```

---

## 🗑 削除

```bash
aws cloudformation delete-stack \
  --stack-name step5-dns
```

---

# 🔁 1日の開発フロー（Pod Identity版）

---

## 起動

```bash
step1 → step2 → step3 → step4 → step5
```

---

## 終了

```bash
kubectl delete all --all

helm uninstall karpenter -n karpenter
helm uninstall aws-load-balancer-controller -n kube-system

aws cloudformation delete-stack step5-dns
aws cloudformation delete-stack step4-alb-iam
aws cloudformation delete-stack step3-karpenter-iam
aws cloudformation delete-stack step1-eks
```

---

# 🚨 重要注意（Pod Identity特有）

---

## ① association削除忘れるとハマる

👉 EKS削除時に失敗する

---

## ② ServiceAccount名は完全一致

```text
namespace + name
```

---

## ③ Pod Identity Agent確認

```bash
kubectl get pods -n kube-system
```

---

# 🎯 まとめ

---

## Pod Identity版の特徴

* OIDC不要
* IAMシンプル
* association管理がコア

---

## Step3-5の役割

| Step  | 内容     |
| ----- | ------ |
| Step3 | ノード自動化 |
| Step4 | L7公開   |
| Step5 | DNS    |

---

---

ここまでできれば👇

👉 **完全に“EKS上でサービスを構築できる状態”**

---
