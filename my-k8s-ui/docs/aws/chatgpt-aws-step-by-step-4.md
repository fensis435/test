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
  VPC:
    Type: AWS::EC2::VPC::Id # Specify VPC using CLI parameters.
  RouteTableId:
    Type: String
    Description: Route Table ID for the VPC

Resources:
# ------------------------
# VPC (case: New VPC)
# ------------------------
#  VPC:
#    Type: AWS::EC2::VPC
#    Properties:
#      CidrBlock: 10.0.0.0/16
#      EnableDnsSupport: true
#      EnableDnsHostnames: true

# ------------------------
# Subnets (Private Only)
# ------------------------
  PrivateSubnetA:
    Type: AWS::EC2::Subnet
    Properties:
      VpcId: !Ref VPC
      CidrBlock: 10.0.1.0/24
      AvailabilityZone: ap-northeast-1a
      Tags:
        - Key: Name
          Value: !Sub "${ClusterName}-subnet-a"
        - Key: "kubernetes.io/role/internal-elb"
          Value: "1"

  PrivateSubnetB:
    Type: AWS::EC2::Subnet
    Properties:
      VpcId: !Ref VPC
      CidrBlock: 10.0.2.0/24
      AvailabilityZone: ap-northeast-1c
      Tags:
        - Key: Name
          Value: !Sub "${ClusterName}-subnet-b"
        - Key: "kubernetes.io/role/internal-elb"
          Value: "1"

# ------------------------
# Security Group
# ------------------------
  EKSSG:
    Type: AWS::EC2::SecurityGroup
    Properties:
      GroupDescription: EKS and Endpoint SG
      VpcId: !Ref VPC
      SecurityGroupIngress:
        - IpProtocol: -1
          FromPort: -1
          ToPort: -1
          CidrIp: 10.0.0.0/16 # VPC内通信を許可

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
        - arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore # SSMログイン用

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
    DependsOn: EKSCluster # クラスターができてから作成
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
      ServiceName: !Sub "com.amazonaws.${AWS::Region}.s3"
      VpcEndpointType: Gateway
      RouteTableIds: 
        - !Ref RouteTableId

  ECREndpoint:
    Type: AWS::EC2::VPCEndpoint
    Properties:
      VpcId: !Ref VPC
      ServiceName: !Sub "com.amazonaws.${AWS::Region}.ecr.api"
      VpcEndpointType: Interface
      SubnetIds:
        - !Ref PrivateSubnetA
        - !Ref PrivateSubnetB
      SecurityGroupIds: [!Ref EKSSG]

  ECRDockerEndpoint:
    Type: AWS::EC2::VPCEndpoint
    Properties:
      VpcId: !Ref VPC
      ServiceName: !Sub "com.amazonaws.${AWS::Region}.ecr.dkr"
      VpcEndpointType: Interface
      SubnetIds:
        - !Ref PrivateSubnetA
        - !Ref PrivateSubnetB
      SecurityGroupIds: [!Ref EKSSG]

  STSEndpoint: # プライベート環境でのIAM認証に必要
    Type: AWS::EC2::VPCEndpoint
    Properties:
      VpcId: !Ref VPC
      ServiceName: !Sub "com.amazonaws.${AWS::Region}.sts"
      VpcEndpointType: Interface
      SubnetIds:
        - !Ref PrivateSubnetA
        - !Ref PrivateSubnetB
      SecurityGroupIds: [!Ref EKSSG]

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
aws ec2 describe-vpcs \
  --query "Vpcs[].[{CIDR:CidrBlock,Name:Tags[0].Value,VpcId:VpcId}]" \
   --out table

aws ec2 describe-route-tables \
  --filters "Name=vpc-id,Values=vpc-xxxxxxxxxxxxxxxxx" \
  --query "RouteTables[*].RouteTableId" \
  --output text

aws cloudformation deploy \
  --stack-name foundation \
  --template-file step0-foundation.yaml \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides \
      VPC=vpc-0123456789 \
      RouteTableId=rtb-0123456789 \
      ClusterName=my-eks
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
