---

# 🎯 ゴール

このテンプレで作るもの👇

```text
VPC
 ├─ Private Subnet x2
 ├─ VPC Endpoint（ECR/S3等）
 ├─ Security Group
 └─ EKS Cluster（Private Endpoint）
     └─ Managed Node Group
```

---

# 🧱 フルCFnテンプレ（step0-foundation.yaml）

```yaml
AWSTemplateFormatVersion: '2010-09-09'
Description: Full Private EKS Foundation

Parameters:
  ClusterName:
    Type: String
    Default: my-eks

Resources:

# ------------------------
# VPC
# ------------------------
  VPC:
    Type: AWS::EC2::VPC
    Properties:
      CidrBlock: 10.0.0.0/16
      EnableDnsSupport: true
      EnableDnsHostnames: true

# ------------------------
# Subnets (Private Only)
# ------------------------
  PrivateSubnetA:
    Type: AWS::EC2::Subnet
    Properties:
      VpcId: !Ref VPC
      CidrBlock: 10.0.1.0/24
      AvailabilityZone: ap-northeast-1a

  PrivateSubnetB:
    Type: AWS::EC2::Subnet
    Properties:
      VpcId: !Ref VPC
      CidrBlock: 10.0.2.0/24
      AvailabilityZone: ap-northeast-1c

# ------------------------
# Security Group
# ------------------------
  EKSSG:
    Type: AWS::EC2::SecurityGroup
    Properties:
      GroupDescription: EKS SG
      VpcId: !Ref VPC

# ------------------------
# IAM Roles
# ------------------------
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

# ------------------------
# EKS Cluster（Private）
# ------------------------
  EKSCluster:
    Type: AWS::EKS::Cluster
    Properties:
      Name: !Ref ClusterName
      RoleArn: !GetAtt EKSClusterRole.Arn
      ResourcesVpcConfig:
        SubnetIds:
          - !Ref PrivateSubnetA
          - !Ref PrivateSubnetB
        EndpointPrivateAccess: true
        EndpointPublicAccess: false
        SecurityGroupIds:
          - !Ref EKSSG

# ------------------------
# Node Group
# ------------------------
  NodeGroup:
    Type: AWS::EKS::Nodegroup
    Properties:
      ClusterName: !Ref ClusterName
      NodeRole: !GetAtt NodeRole.Arn
      Subnets:
        - !Ref PrivateSubnetA
        - !Ref PrivateSubnetB
      ScalingConfig:
        DesiredSize: 2
        MinSize: 1
        MaxSize: 3
      InstanceTypes:
        - t3.medium

# ------------------------
# VPC Endpoints（重要）
# ------------------------

  S3Endpoint:
    Type: AWS::EC2::VPCEndpoint
    Properties:
      VpcId: !Ref VPC
      ServiceName: com.amazonaws.ap-northeast-1.s3
      VpcEndpointType: Gateway

  ECREndpoint:
    Type: AWS::EC2::VPCEndpoint
    Properties:
      VpcId: !Ref VPC
      ServiceName: com.amazonaws.ap-northeast-1.ecr.api
      VpcEndpointType: Interface
      SubnetIds:
        - !Ref PrivateSubnetA
        - !Ref PrivateSubnetB

  ECRDockerEndpoint:
    Type: AWS::EC2::VPCEndpoint
    Properties:
      VpcId: !Ref VPC
      ServiceName: com.amazonaws.ap-northeast-1.ecr.dkr
      VpcEndpointType: Interface
      SubnetIds:
        - !Ref PrivateSubnetA
        - !Ref PrivateSubnetB

Outputs:
  ClusterName:
    Value: !Ref ClusterName

  VpcId:
    Value: !Ref VPC

  Subnets:
    Value: !Join [",", [!Ref PrivateSubnetA, !Ref PrivateSubnetB]]
```

---

# ▶️ デプロイ

```bash
aws cloudformation deploy \
  --stack-name foundation \
  --template-file step0-foundation.yaml \
  --capabilities CAPABILITY_NAMED_IAM
```

---

# 🔍 確認

```bash
aws eks describe-cluster --name my-eks
```

---

```bash
aws ec2 describe-vpcs
```

---

# 🔗 kubectl接続（SSM前提）

```bash
aws eks update-kubeconfig --name my-eks
kubectl get nodes
```

---

# 🗑 削除（重要）

```bash
aws cloudformation delete-stack \
  --stack-name foundation
```

---

# 🚨 このテンプレのポイント

---

## ✔ 完全private

* public subnetなし
* EKS endpoint private only

---

## ✔ NAT不要

👉 代わりに👇

* S3 Endpoint
* ECR Endpoint

---

## ✔ 最小構成

👉 ここにあとで足す：

* Karpenter
* ALB Controller
* Route53

---

# 🔥 実務で追加すべきもの（次）

---

## Step1追加

* SSM用EC2（踏み台）

---

## Step2追加

* Pod Identity roles

---

## Step3追加

* ALB（internal）

---

# 💡 改良ポイント（プロ向け）

---

## ① STS Endpoint追加

```yaml
com.amazonaws.ap-northeast-1.sts
```

---

## ② Logs Endpoint

```yaml
com.amazonaws.ap-northeast-1.logs
```

---

## ③ EKS Addon

* CoreDNS
* VPC CNI

---

# 🎯 最終まとめ

---

## このテンプレで

👉 **完全privateなEKS基盤が一発で立つ**

---

## その上に

* Karpenter
* nginx
* envoy
* ALB
* DNS

---

👉 あなたの構成が完成する

---
