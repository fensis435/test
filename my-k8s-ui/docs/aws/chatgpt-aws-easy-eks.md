ここは**後工程（EKS + CodeBuild + 完全Private）まで見据えたIAM設計**として、**CloudFormationテンプレート形式＋理由**で整理します。

---

# 🎯 前提

対象構成：

* Amazon Web Services 上で完全Private
* Amazon EKS
* AWS CodeBuild（将来使用）
* 踏み台EC2（SSM）

---

# 🧱 必要なIAMロール一覧（全体像）

| ロール名                        | 用途                |
| --------------------------- | ----------------- |
| BastionRole                 | 踏み台EC2            |
| CloudFormationExecutionRole | CFn実行             |
| EKSClusterRole              | EKS control plane |
| EKSNodeInstanceRole         | Workerノード         |
| CodeBuildServiceRole        | CodeBuild         |

---

# ① 踏み台EC2用ロール

## YAML

```yaml
AWSTemplateFormatVersion: '2010-09-09'
Resources:
  BastionRole:
    Type: AWS::IAM::Role
    Properties:
      RoleName: BastionRole
      AssumeRolePolicyDocument:
        Version: '2012-10-17'
        Statement:
          - Effect: Allow
            Principal:
              Service: ec2.amazonaws.com
            Action: sts:AssumeRole
      ManagedPolicyArns:
        - arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
        - arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly

  BastionInstanceProfile:
    Type: AWS::IAM::InstanceProfile
    Properties:
      Roles:
        - !Ref BastionRole
```

## なぜ必要か

* SSMログイン（SSH不要）
* ECRからイメージ取得確認
* kubectl操作の踏み台

👉 完全Privateでは**唯一の操作端末**

---

# ② CloudFormation実行ロール

## YAML

```yaml
Resources:
  CloudFormationExecutionRole:
    Type: AWS::IAM::Role
    Properties:
      RoleName: CFnExecutionRole
      AssumeRolePolicyDocument:
        Version: '2012-10-17'
        Statement:
          - Effect: Allow
            Principal:
              Service: cloudformation.amazonaws.com
            Action: sts:AssumeRole
      Policies:
        - PolicyName: CFnFullAccessForEKS
          PolicyDocument:
            Version: '2012-10-17'
            Statement:
              - Effect: Allow
                Action:
                  - eks:*
                  - ec2:*
                  - iam:PassRole
                  - logs:*
                Resource: "*"
```

## なぜ必要か

* CloudFormationがリソース作成するため
* `--role-arn` 指定で使用

👉 権限を分離することで：

* 操作ユーザの権限最小化
* 監査対応

---

# ③ EKSクラスタロール

## YAML

```yaml
Resources:
  EKSClusterRole:
    Type: AWS::IAM::Role
    Properties:
      RoleName: EKSClusterRole
      AssumeRolePolicyDocument:
        Version: '2012-10-17'
        Statement:
          - Effect: Allow
            Principal:
              Service: eks.amazonaws.com
            Action: sts:AssumeRole
      ManagedPolicyArns:
        - arn:aws:iam::aws:policy/AmazonEKSClusterPolicy
```

## なぜ必要か

* EKS control planeがAWSリソース操作するため

具体例：

* ENI作成
* LoadBalancer連携
* ログ出力

👉 **EKSの中枢ロール**

---

# ④ ノードグループ用ロール（超重要）

## YAML

```yaml
Resources:
  EKSNodeInstanceRole:
    Type: AWS::IAM::Role
    Properties:
      RoleName: EKSNodeInstanceRole
      AssumeRolePolicyDocument:
        Version: '2012-10-17'
        Statement:
          - Effect: Allow
            Principal:
              Service: ec2.amazonaws.com
            Action: sts:AssumeRole
      ManagedPolicyArns:
        - arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy
        - arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly
        - arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy
```

## なぜ必要か

これがないと**100%詰みます**

ノードは起動時に👇をやる：

* EKSに参加（kubelet）
* ECRからイメージpull
* CNIでネットワーク設定

👉 完全Privateでは特に重要

---

# ⑤ CodeBuild用ロール（将来必須）

## YAML

```yaml
Resources:
  CodeBuildServiceRole:
    Type: AWS::IAM::Role
    Properties:
      RoleName: CodeBuildRole
      AssumeRolePolicyDocument:
        Version: '2012-10-17'
        Statement:
          - Effect: Allow
            Principal:
              Service: codebuild.amazonaws.com
            Action: sts:AssumeRole
      Policies:
        - PolicyName: CodeBuildAccess
          PolicyDocument:
            Version: '2012-10-17'
            Statement:
              - Effect: Allow
                Action:
                  - ecr:*
                  - logs:*
                  - s3:*
                  - eks:DescribeCluster
                Resource: "*"
```

## なぜ必要か

CodeBuildがやること👇

* Docker build → ECR push
* S3にartifact保存
* EKSへデプロイ（kubectl）

👉 **CI/CDの実行主体**

---

# 🧠 重要な設計ポイント

## ① iam:PassRole の意味

CloudFormationロールに必要

👉 理由：

* EKS作成時に

  * ClusterRole
  * NodeRole
    を渡す必要がある

---

## ② 最小権限にするなら

本番では👇やる

* Resourceを絞る
* Actionを限定

ただし最初は広めでOK

---

## ③ 完全Privateで効いてくるIAM

特に重要👇

* ECR権限
* STS（AssumeRole）
* SSM

👉 通信できてもIAMで弾かれるケース多い

---

# 👍 まとめ

あなたの構成に必要なIAMはこの5つ：

1. Bastion（操作）
2. CloudFormation（構築）
3. EKS Cluster（制御）
4. Node（実行）
5. CodeBuild（CI/CD）

---
---

**完全Private + EKS + 将来CodeBuild前提**で、**“そのままコピペして使えるVPC Endpoint一覧（CloudFormation）”**を出します。

---

# 🎯 前提

* 完全Private（NATなし）
* Amazon EKS
* AWS CodeBuild（将来）
* 踏み台EC2（SSM）

---

# 🧱 ① まず全体一覧（これ全部必要）

## ✔ Gateway Endpoint

* S3（最重要）

## ✔ Interface Endpoint

* EC2
* EKS
* ECR（api / dkr）
* STS
* Logs
* SSM（3種）
* CodeBuild
* AutoScaling
* ELB

---

# 🔥 コピペ用 CloudFormation（完全版）

※ パラメータは最低限にしてあります

---

## ① パラメータ + SG

```yaml
Parameters:
  VpcId:
    Type: AWS::EC2::VPC::Id

  PrivateSubnetIds:
    Type: List<AWS::EC2::Subnet::Id>

Resources:
  EndpointSG:
    Type: AWS::EC2::SecurityGroup
    Properties:
      GroupDescription: Endpoint SG
      VpcId: !Ref VpcId
      SecurityGroupIngress:
        - IpProtocol: -1
          CidrIp: 10.0.0.0/8
```

---

## ② S3 Gateway Endpoint（最重要）

```yaml
  S3Endpoint:
    Type: AWS::EC2::VPCEndpoint
    Properties:
      VpcId: !Ref VpcId
      ServiceName: !Sub com.amazonaws.${AWS::Region}.s3
      VpcEndpointType: Gateway
      RouteTableIds:
        - rtb-xxxxxxxx  # ←差し替え必要
```

---

## ③ Interface Endpoint（全部入り）

```yaml
  EC2Endpoint:
    Type: AWS::EC2::VPCEndpoint
    Properties:
      VpcId: !Ref VpcId
      ServiceName: !Sub com.amazonaws.${AWS::Region}.ec2
      VpcEndpointType: Interface
      SubnetIds: !Ref PrivateSubnetIds
      SecurityGroupIds: [!Ref EndpointSG]
      PrivateDnsEnabled: true

  EKSEndpoint:
    Type: AWS::EC2::VPCEndpoint
    Properties:
      VpcId: !Ref VpcId
      ServiceName: !Sub com.amazonaws.${AWS::Region}.eks
      VpcEndpointType: Interface
      SubnetIds: !Ref PrivateSubnetIds
      SecurityGroupIds: [!Ref EndpointSG]
      PrivateDnsEnabled: true

  ECRApiEndpoint:
    Type: AWS::EC2::VPCEndpoint
    Properties:
      VpcId: !Ref VpcId
      ServiceName: !Sub com.amazonaws.${AWS::Region}.ecr.api
      VpcEndpointType: Interface
      SubnetIds: !Ref PrivateSubnetIds
      SecurityGroupIds: [!Ref EndpointSG]
      PrivateDnsEnabled: true

  ECRDkrEndpoint:
    Type: AWS::EC2::VPCEndpoint
    Properties:
      VpcId: !Ref VpcId
      ServiceName: !Sub com.amazonaws.${AWS::Region}.ecr.dkr
      VpcEndpointType: Interface
      SubnetIds: !Ref PrivateSubnetIds
      SecurityGroupIds: [!Ref EndpointSG]
      PrivateDnsEnabled: true

  STSEndpoint:
    Type: AWS::EC2::VPCEndpoint
    Properties:
      VpcId: !Ref VpcId
      ServiceName: !Sub com.amazonaws.${AWS::Region}.sts
      VpcEndpointType: Interface
      SubnetIds: !Ref PrivateSubnetIds
      SecurityGroupIds: [!Ref EndpointSG]
      PrivateDnsEnabled: true

  LogsEndpoint:
    Type: AWS::EC2::VPCEndpoint
    Properties:
      VpcId: !Ref VpcId
      ServiceName: !Sub com.amazonaws.${AWS::Region}.logs
      VpcEndpointType: Interface
      SubnetIds: !Ref PrivateSubnetIds
      SecurityGroupIds: [!Ref EndpointSG]
      PrivateDnsEnabled: true
```

---

## ④ SSM（3点セット）

```yaml
  SSMEndpoint:
    Type: AWS::EC2::VPCEndpoint
    Properties:
      VpcId: !Ref VpcId
      ServiceName: !Sub com.amazonaws.${AWS::Region}.ssm
      VpcEndpointType: Interface
      SubnetIds: !Ref PrivateSubnetIds
      SecurityGroupIds: [!Ref EndpointSG]
      PrivateDnsEnabled: true

  SSMMessagesEndpoint:
    Type: AWS::EC2::VPCEndpoint
    Properties:
      VpcId: !Ref VpcId
      ServiceName: !Sub com.amazonaws.${AWS::Region}.ssmmessages
      VpcEndpointType: Interface
      SubnetIds: !Ref PrivateSubnetIds
      SecurityGroupIds: [!Ref EndpointSG]
      PrivateDnsEnabled: true

  EC2MessagesEndpoint:
    Type: AWS::EC2::VPCEndpoint
    Properties:
      VpcId: !Ref VpcId
      ServiceName: !Sub com.amazonaws.${AWS::Region}.ec2messages
      VpcEndpointType: Interface
      SubnetIds: !Ref PrivateSubnetIds
      SecurityGroupIds: [!Ref EndpointSG]
      PrivateDnsEnabled: true
```

---

## ⑤ CodeBuild + 追加系

```yaml
  CodeBuildEndpoint:
    Type: AWS::EC2::VPCEndpoint
    Properties:
      VpcId: !Ref VpcId
      ServiceName: !Sub com.amazonaws.${AWS::Region}.codebuild
      VpcEndpointType: Interface
      SubnetIds: !Ref PrivateSubnetIds
      SecurityGroupIds: [!Ref EndpointSG]
      PrivateDnsEnabled: true

  AutoScalingEndpoint:
    Type: AWS::EC2::VPCEndpoint
    Properties:
      VpcId: !Ref VpcId
      ServiceName: !Sub com.amazonaws.${AWS::Region}.autoscaling
      VpcEndpointType: Interface
      SubnetIds: !Ref PrivateSubnetIds
      SecurityGroupIds: [!Ref EndpointSG]
      PrivateDnsEnabled: true

  ELBEndpoint:
    Type: AWS::EC2::VPCEndpoint
    Properties:
      VpcId: !Ref VpcId
      ServiceName: !Sub com.amazonaws.${AWS::Region}.elasticloadbalancing
      VpcEndpointType: Interface
      SubnetIds: !Ref PrivateSubnetIds
      SecurityGroupIds: [!Ref EndpointSG]
      PrivateDnsEnabled: true
```

---

# ⚠️ 重要注意（ここでハマる）

## ① Private DNSは必ず true

これないと：
👉 `*.amazonaws.com` が解決できず死亡

---

## ② S3 Gatewayはルートテーブル必須

```text
pl-xxxx (S3 prefix list) → vpce
```

---

## ③ SecurityGroupの範囲

本番は👇にする

```text
VPC CIDRのみに限定
```

---

# 🧠 最小構成に削ると？

最初だけなら👇でも可

* S3
* ECR(api + dkr)
* STS
* EC2
* EKS
* SSM（3つ）

---

# 👍 まとめ

このテンプレで👇が成立

* EKS起動
* ノード参加
* ECR pull
* SSMログイン
* CodeBuild準備

---
---

ここでは**「完全Privateで動く最小構成の Amazon EKS クラスタ」**を、**CloudFormationでそのまま使える形**で出します。
（NGINX Pod起動までいける構成）

---

# 🎯 前提（このテンプレの思想）

* Public Endpoint ❌（完全Private）
* NAT ❌
* VPC Endpoint前提（前に出した②）
* Managed Node Group使用
* 最小構成（まず動かすこと優先）

---

# 🧱 CloudFormation（EKS Private完全版）

---

## ① パラメータ

```yaml
AWSTemplateFormatVersion: '2010-09-09'
Description: Private EKS Cluster

Parameters:
  ClusterName:
    Type: String
    Default: private-eks

  VpcId:
    Type: AWS::EC2::VPC::Id

  PrivateSubnetIds:
    Type: List<AWS::EC2::Subnet::Id>

  NodeInstanceType:
    Type: String
    Default: t3.medium
```

---

## ② EKSクラスタロール

```yaml
Resources:
  EKSClusterRole:
    Type: AWS::IAM::Role
    Properties:
      RoleName: !Sub ${ClusterName}-ClusterRole
      AssumeRolePolicyDocument:
        Version: '2012-10-17'
        Statement:
          - Effect: Allow
            Principal:
              Service: eks.amazonaws.com
            Action: sts:AssumeRole
      ManagedPolicyArns:
        - arn:aws:iam::aws:policy/AmazonEKSClusterPolicy
```

---

## ③ ノードロール

```yaml
  NodeInstanceRole:
    Type: AWS::IAM::Role
    Properties:
      RoleName: !Sub ${ClusterName}-NodeRole
      AssumeRolePolicyDocument:
        Version: '2012-10-17'
        Statement:
          - Effect: Allow
            Principal:
              Service: ec2.amazonaws.com
            Action: sts:AssumeRole
      ManagedPolicyArns:
        - arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy
        - arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy
        - arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly

  NodeInstanceProfile:
    Type: AWS::IAM::InstanceProfile
    Properties:
      Roles:
        - !Ref NodeInstanceRole
```

---

## ④ セキュリティグループ

```yaml
  ClusterSecurityGroup:
    Type: AWS::EC2::SecurityGroup
    Properties:
      GroupDescription: EKS Cluster SG
      VpcId: !Ref VpcId
```

---

## ⑤ EKSクラスタ（Private設定が核心）

```yaml
  EKSCluster:
    Type: AWS::EKS::Cluster
    Properties:
      Name: !Ref ClusterName
      Version: "1.29"
      RoleArn: !GetAtt EKSClusterRole.Arn
      ResourcesVpcConfig:
        SubnetIds: !Ref PrivateSubnetIds
        SecurityGroupIds:
          - !Ref ClusterSecurityGroup
        EndpointPublicAccess: false
        EndpointPrivateAccess: true
```

---

## ⑥ Node Group（ここも重要）

```yaml
  NodeGroup:
    Type: AWS::EKS::Nodegroup
    DependsOn: EKSCluster
    Properties:
      ClusterName: !Ref ClusterName
      NodeRole: !GetAtt NodeInstanceRole.Arn
      Subnets: !Ref PrivateSubnetIds
      ScalingConfig:
        DesiredSize: 2
        MinSize: 1
        MaxSize: 3
      InstanceTypes:
        - !Ref NodeInstanceType
      AmiType: AL2_x86_64
```

---

## ⑦ Output

```yaml
Outputs:
  ClusterName:
    Value: !Ref ClusterName
```

---

# 🔥 ここが重要（絶対チェック）

## ① これがないと100%失敗

事前に必要👇

* VPC Endpoint一式（前に出したやつ）
* S3 Gateway Endpoint
* ECR(api + dkr)
* STS

---

## ② Nodeが起動しないときの原因TOP3

### ❌ 1位

ECR Endpoint不足
👉 イメージpull失敗

---

### ❌ 2位

STS Endpoint不足
👉 ノード認証失敗

---

### ❌ 3位

S3 Endpointなし
👉 ECR layer取得失敗

---

# 🧪 デプロイ後の流れ

踏み台EC2（SSM）から👇

---

## ① kubeconfig取得

```bash
aws eks update-kubeconfig \
  --name private-eks \
  --region ap-northeast-1
```

---

## ② ノード確認

```bash
kubectl get nodes
```

---

## ③ nginxデプロイ（ECR版）

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
        - name: nginx
          image: <ECRのnginx>
          ports:
            - containerPort: 80
```

---

# 🧠 設計のポイント

## なぜこれで動くか

* EKS API → Private Endpoint
* Node → Endpoint経由でECR/STSアクセス
* kubectl → 踏み台からPrivate接続

👉 完全閉域で成立

---

# 👍 次のステップ（かなり重要）

ここまで来たら👇

---

## ① aws-auth ConfigMap設定

（ノードがJoin済でも必要なケースあり）

---

## ② CodeBuildからkubectl叩く

→ 本命

---

## ③ Ingress（内部LB）

→ サービス確認

---
---

**Access Entry込み・完全Private対応のフルCloudFormationテンプレート**を提示します。
（そのままベースとして使える実務レベル構成）

---

# 🎯 このテンプレの特徴

* Amazon EKS Private Cluster
* NATなし前提
* Managed Node Group
* Access Entryで認可（aws-auth不要）
* Bastion / CodeBuildからkubectl可能

---

# 🧱 フルCloudFormation（Access Entry統合版）

```yaml
AWSTemplateFormatVersion: '2010-09-09'
Description: Private EKS Cluster with Access Entry

Parameters:
  ClusterName:
    Type: String
    Default: private-eks

  VpcId:
    Type: AWS::EC2::VPC::Id

  PrivateSubnetIds:
    Type: List<AWS::EC2::Subnet::Id>

  NodeInstanceType:
    Type: String
    Default: t3.medium

  BastionRoleArn:
    Type: String

  CodeBuildRoleArn:
    Type: String

Resources:

  # =========================
  # EKS Cluster Role
  # =========================
  EKSClusterRole:
    Type: AWS::IAM::Role
    Properties:
      RoleName: !Sub ${ClusterName}-ClusterRole
      AssumeRolePolicyDocument:
        Version: '2012-10-17'
        Statement:
          - Effect: Allow
            Principal:
              Service: eks.amazonaws.com
            Action: sts:AssumeRole
      ManagedPolicyArns:
        - arn:aws:iam::aws:policy/AmazonEKSClusterPolicy

  # =========================
  # Node Role
  # =========================
  NodeInstanceRole:
    Type: AWS::IAM::Role
    Properties:
      RoleName: !Sub ${ClusterName}-NodeRole
      AssumeRolePolicyDocument:
        Version: '2012-10-17'
        Statement:
          - Effect: Allow
            Principal:
              Service: ec2.amazonaws.com
            Action: sts:AssumeRole
      ManagedPolicyArns:
        - arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy
        - arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy
        - arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly

  # =========================
  # Security Group
  # =========================
  ClusterSecurityGroup:
    Type: AWS::EC2::SecurityGroup
    Properties:
      GroupDescription: EKS Cluster SG
      VpcId: !Ref VpcId

  # =========================
  # EKS Cluster (Private)
  # =========================
  EKSCluster:
    Type: AWS::EKS::Cluster
    Properties:
      Name: !Ref ClusterName
      Version: "1.29"
      RoleArn: !GetAtt EKSClusterRole.Arn
      ResourcesVpcConfig:
        SubnetIds: !Ref PrivateSubnetIds
        SecurityGroupIds:
          - !Ref ClusterSecurityGroup
        EndpointPublicAccess: false
        EndpointPrivateAccess: true

  # =========================
  # Node Group
  # =========================
  NodeGroup:
    Type: AWS::EKS::Nodegroup
    DependsOn: EKSCluster
    Properties:
      ClusterName: !Ref ClusterName
      NodeRole: !GetAtt NodeInstanceRole.Arn
      Subnets: !Ref PrivateSubnetIds
      ScalingConfig:
        DesiredSize: 2
        MinSize: 1
        MaxSize: 3
      InstanceTypes:
        - !Ref NodeInstanceType
      AmiType: AL2_x86_64

  # =========================
  # Access Entry (Bastion)
  # =========================
  BastionAccessEntry:
    Type: AWS::EKS::AccessEntry
    Properties:
      ClusterName: !Ref ClusterName
      PrincipalArn: !Ref BastionRoleArn
      Type: STANDARD

  BastionAccessPolicy:
    Type: AWS::EKS::AccessPolicyAssociation
    Properties:
      ClusterName: !Ref ClusterName
      PrincipalArn: !Ref BastionRoleArn
      PolicyArn: arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy
      AccessScope:
        Type: cluster

  # =========================
  # Access Entry (CodeBuild)
  # =========================
  CodeBuildAccessEntry:
    Type: AWS::EKS::AccessEntry
    Properties:
      ClusterName: !Ref ClusterName
      PrincipalArn: !Ref CodeBuildRoleArn
      Type: STANDARD

  CodeBuildAccessPolicy:
    Type: AWS::EKS::AccessPolicyAssociation
    Properties:
      ClusterName: !Ref ClusterName
      PrincipalArn: !Ref CodeBuildRoleArn
      PolicyArn: arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy
      AccessScope:
        Type: cluster

Outputs:
  ClusterName:
    Value: !Ref ClusterName
```

---

# 🔥 重要ポイント（実務で詰まるところ）

## ① Nodeはaws-auth不要

👉 Managed Node Groupなら自動登録
（昔の知識と違う最大ポイント）

---

## ② Bastion / CodeBuildはAccess Entryで制御

👉 aws-auth完全不要

---

## ③ それでもIAMは必要

踏み台ロールに最低限👇

```yaml
eks:DescribeCluster
```

---

## ④ VPC Endpointが前提

これがないと👇

* Node参加失敗
* ECR pull失敗
* kubectl失敗

---

# 🚀 デプロイ後の流れ

踏み台EC2から👇

```bash
aws eks update-kubeconfig --name private-eks
kubectl get nodes
```

---

# 🧠 設計の本質

今回の構成は👇

👉 **「aws-authを排除したモダンEKS構成」**

---

# 👍 これでできること

* 完全PrivateでEKS起動
* Node自動Join
* Bastionからkubectl
* CodeBuildからデプロイ準備完了

---

# 👉 次にやるべき（重要）

ここまで来たら👇

## ① nginxを“確実に起動する”ECR対応YAML

## ② CodeBuildからkubectl実行（完全手順）

## ③ Private環境でのトラブルシュート集

---
---

ここでは **「EKS + Node + Access Entry + CodeBuild（VPC内実行）」までを1スタックで構築する完成版」**を提示します。

---

# 🎯 前提（重要）

このテンプレは以下を**外部前提**とします：

### ✔ 事前に用意済み

* VPC（踏み台EC2あり）
* Private Subnet（EKS用）
* VPC Endpoint一式（ECR / S3 / STS / EKS / Logs / CodeBuild など）
* IAMロール：

  * BastionRole
  * CodeBuildRole
  * CloudFormation実行ロール（スタック実行時に使用）

👉 この分離は正しいです（監査的にもベスト）

---

# 🧱 フルCloudFormation（完成版）

```yaml
AWSTemplateFormatVersion: '2010-09-09'
Description: Private EKS + CodeBuild (One Stack)

Parameters:
  ClusterName:
    Type: String
    Default: private-eks

  VpcId:
    Type: AWS::EC2::VPC::Id

  PrivateSubnetIds:
    Type: List<AWS::EC2::Subnet::Id>

  NodeInstanceType:
    Type: String
    Default: t3.medium

  BastionRoleArn:
    Type: String

  CodeBuildRoleArn:
    Type: String

Resources:

# =========================
# EKS Cluster Role
# =========================
  EKSClusterRole:
    Type: AWS::IAM::Role
    Properties:
      RoleName: !Sub ${ClusterName}-ClusterRole
      AssumeRolePolicyDocument:
        Version: '2012-10-17'
        Statement:
          - Effect: Allow
            Principal:
              Service: eks.amazonaws.com
            Action: sts:AssumeRole
      ManagedPolicyArns:
        - arn:aws:iam::aws:policy/AmazonEKSClusterPolicy

# =========================
# Node Role
# =========================
  NodeInstanceRole:
    Type: AWS::IAM::Role
    Properties:
      RoleName: !Sub ${ClusterName}-NodeRole
      AssumeRolePolicyDocument:
        Version: '2012-10-17'
        Statement:
          - Effect: Allow
            Principal:
              Service: ec2.amazonaws.com
            Action: sts:AssumeRole
      ManagedPolicyArns:
        - arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy
        - arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy
        - arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly

# =========================
# Security Group
# =========================
  ClusterSecurityGroup:
    Type: AWS::EC2::SecurityGroup
    Properties:
      GroupDescription: EKS Cluster SG
      VpcId: !Ref VpcId

# =========================
# EKS Cluster (Private)
# =========================
  EKSCluster:
    Type: AWS::EKS::Cluster
    Properties:
      Name: !Ref ClusterName
      Version: "1.29"
      RoleArn: !GetAtt EKSClusterRole.Arn
      ResourcesVpcConfig:
        SubnetIds: !Ref PrivateSubnetIds
        SecurityGroupIds:
          - !Ref ClusterSecurityGroup
        EndpointPublicAccess: false
        EndpointPrivateAccess: true

# =========================
# Node Group
# =========================
  NodeGroup:
    Type: AWS::EKS::Nodegroup
    DependsOn: EKSCluster
    Properties:
      ClusterName: !Ref ClusterName
      NodeRole: !GetAtt NodeInstanceRole.Arn
      Subnets: !Ref PrivateSubnetIds
      ScalingConfig:
        DesiredSize: 2
        MinSize: 1
        MaxSize: 3
      InstanceTypes:
        - !Ref NodeInstanceType
      AmiType: AL2_x86_64

# =========================
# Access Entry (Bastion)
# =========================
  BastionAccessEntry:
    Type: AWS::EKS::AccessEntry
    Properties:
      ClusterName: !Ref ClusterName
      PrincipalArn: !Ref BastionRoleArn
      Type: STANDARD

  BastionAccessPolicy:
    Type: AWS::EKS::AccessPolicyAssociation
    Properties:
      ClusterName: !Ref ClusterName
      PrincipalArn: !Ref BastionRoleArn
      PolicyArn: arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy
      AccessScope:
        Type: cluster

# =========================
# Access Entry (CodeBuild)
# =========================
  CodeBuildAccessEntry:
    Type: AWS::EKS::AccessEntry
    Properties:
      ClusterName: !Ref ClusterName
      PrincipalArn: !Ref CodeBuildRoleArn
      Type: STANDARD

  CodeBuildAccessPolicy:
    Type: AWS::EKS::AccessPolicyAssociation
    Properties:
      ClusterName: !Ref ClusterName
      PrincipalArn: !Ref CodeBuildRoleArn
      PolicyArn: arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy
      AccessScope:
        Type: cluster

# =========================
# CodeBuild Project（VPC内実行）
# =========================
  CodeBuildProject:
    Type: AWS::CodeBuild::Project
    Properties:
      Name: !Sub ${ClusterName}-build
      ServiceRole: !Ref CodeBuildRoleArn
      Artifacts:
        Type: NO_ARTIFACTS
      Environment:
        ComputeType: BUILD_GENERAL1_SMALL
        Image: aws/codebuild/standard:7.0
        Type: LINUX_CONTAINER
        PrivilegedMode: true
      Source:
        Type: NO_SOURCE
        BuildSpec: |
          version: 0.2
          phases:
            install:
              commands:
                - echo installing kubectl
                - curl -o kubectl https://s3.amazonaws.com/amazon-eks/1.29.0/2024-01-04/bin/linux/amd64/kubectl
                - chmod +x kubectl
                - mv kubectl /usr/local/bin/
            build:
              commands:
                - aws eks update-kubeconfig --name ${ClusterName}
                - kubectl get nodes
      VpcConfig:
        VpcId: !Ref VpcId
        Subnets: !Ref PrivateSubnetIds
        SecurityGroupIds:
          - !Ref ClusterSecurityGroup

Outputs:
  ClusterName:
    Value: !Ref ClusterName

  CodeBuildProjectName:
    Value: !Ref CodeBuildProject
```

---

# 🔥 この構成でできること

* 完全PrivateでEKS起動
* Node自動Join
* 踏み台EC2 → kubectl OK
* CodeBuild → VPC内からkubectl実行

---

# ⚠️ 実務での注意点（重要）

## ① CodeBuildが動かない原因TOP

👉 ほぼこれ

* S3 Endpoint不足
* STS Endpoint不足
* ECR Endpoint不足

---

## ② kubectl失敗する場合

* `eks:DescribeCluster` 不足
* Access Entry未作成
* DNS設定ミス

---

## ③ セキュリティ強化（後でやる）

* system:masters → 権限分離
* SGを最小化
* Endpoint制限

---

# 🧠 この構成の価値

👉 **「閉域CI/CD + Kubernetes」まで一気に成立**

---

# 👉 次にやると一気に実務化

おすすめ順👇

### ① ECR + nginx デプロイ（完全閉域版）

### ② CodeBuildでdocker build → ECR push

### ③ Ingress（内部LB）

---
---

ここでは👇を**CloudFormationでそのまま作れる完全版**として提示します：

* BastionRole（踏み台EC2）
* CodeBuildRole（VPC内ビルド）
* CloudFormationExecutionRole（スタック実行）
* SwitchRole（人がAssumeする用）

---

# 🎯 設計前提（重要）

* 人ユーザ → SwitchRole を Assume
* SwitchRole → CloudFormationExecutionRole を Assume
* サービスは各ロールを Assume

👉 **権限分離＋監査対応構成**

---

# 🧱 IAMフルテンプレート（コピペ可）

```yaml
AWSTemplateFormatVersion: '2010-09-09'
Description: IAM Roles for Private EKS + CodeBuild (SwitchRole model)

Parameters:
  TrustedAccountId:
    Type: String
    Description: Account ID allowed to assume SwitchRole

Resources:

# =========================
# Switch Role（人間用）
# =========================
  SwitchRole:
    Type: AWS::IAM::Role
    Properties:
      RoleName: SwitchRole
      AssumeRolePolicyDocument:
        Version: '2012-10-17'
        Statement:
          - Effect: Allow
            Principal:
              AWS: !Sub arn:aws:iam::${TrustedAccountId}:root
            Action: sts:AssumeRole
      Policies:
        - PolicyName: AllowAssumeCFnRole
          PolicyDocument:
            Version: '2012-10-17'
            Statement:
              - Effect: Allow
                Action: sts:AssumeRole
                Resource: !GetAtt CloudFormationExecutionRole.Arn

# =========================
# CloudFormation実行ロール
# =========================
  CloudFormationExecutionRole:
    Type: AWS::IAM::Role
    Properties:
      RoleName: CFnExecutionRole
      AssumeRolePolicyDocument:
        Version: '2012-10-17'
        Statement:
          - Effect: Allow
            Principal:
              Service: cloudformation.amazonaws.com
            Action: sts:AssumeRole
      Policies:
        - PolicyName: CFnExecutionPolicy
          PolicyDocument:
            Version: '2012-10-17'
            Statement:

              # EKS
              - Effect: Allow
                Action:
                  - eks:*
                Resource: "*"

              # EC2 / Networking
              - Effect: Allow
                Action:
                  - ec2:*
                Resource: "*"

              # IAM PassRole（重要）
              - Effect: Allow
                Action:
                  - iam:PassRole
                Resource: "*"

              # Logs
              - Effect: Allow
                Action:
                  - logs:*
                Resource: "*"

              # CodeBuild
              - Effect: Allow
                Action:
                  - codebuild:*
                Resource: "*"

# =========================
# Bastion EC2 Role
# =========================
  BastionRole:
    Type: AWS::IAM::Role
    Properties:
      RoleName: BastionRole
      AssumeRolePolicyDocument:
        Version: '2012-10-17'
        Statement:
          - Effect: Allow
            Principal:
              Service: ec2.amazonaws.com
            Action: sts:AssumeRole
      ManagedPolicyArns:
        - arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
      Policies:
        - PolicyName: BastionAccess
          PolicyDocument:
            Version: '2012-10-17'
            Statement:

              # EKS操作（kubectl前提）
              - Effect: Allow
                Action:
                  - eks:DescribeCluster
                Resource: "*"

              # デバッグ用（ECR pull確認）
              - Effect: Allow
                Action:
                  - ecr:GetAuthorizationToken
                  - ecr:BatchGetImage
                  - ecr:GetDownloadUrlForLayer
                Resource: "*"

  BastionInstanceProfile:
    Type: AWS::IAM::InstanceProfile
    Properties:
      Roles:
        - !Ref BastionRole

# =========================
# CodeBuild Role
# =========================
  CodeBuildRole:
    Type: AWS::IAM::Role
    Properties:
      RoleName: CodeBuildRole
      AssumeRolePolicyDocument:
        Version: '2012-10-17'
        Statement:
          - Effect: Allow
            Principal:
              Service: codebuild.amazonaws.com
            Action: sts:AssumeRole
      Policies:
        - PolicyName: CodeBuildPolicy
          PolicyDocument:
            Version: '2012-10-17'
            Statement:

              # ECR（build/push/pull）
              - Effect: Allow
                Action:
                  - ecr:*
                Resource: "*"

              # S3（artifact）
              - Effect: Allow
                Action:
                  - s3:*
                Resource: "*"

              # Logs
              - Effect: Allow
                Action:
                  - logs:*
                Resource: "*"

              # EKS操作
              - Effect: Allow
                Action:
                  - eks:DescribeCluster
                Resource: "*"

              # STS（必要になるケースあり）
              - Effect: Allow
                Action:
                  - sts:AssumeRole
                Resource: "*"

Outputs:
  SwitchRoleArn:
    Value: !GetAtt SwitchRole.Arn

  CloudFormationExecutionRoleArn:
    Value: !GetAtt CloudFormationExecutionRole.Arn

  BastionRoleArn:
    Value: !GetAtt BastionRole.Arn

  CodeBuildRoleArn:
    Value: !GetAtt CodeBuildRole.Arn
```

---

# 🔥 重要なポイント解説

## ① スイッチロール構造

```text
User → SwitchRole → CloudFormationExecutionRole
```

👉 これで👇が実現

* 人の権限最小化
* 監査ログ明確化
* 誤操作防止

---

## ② iam:PassRole の意味

CloudFormationが👇を渡すために必須

* EKS Cluster Role
* Node Role
* CodeBuild Role

👉 これないと**スタック失敗**

---

## ③ BastionRoleの最小権限

* SSM接続
* kubectl（DescribeCluster）
* デバッグ用ECR

👉 **実運用にちょうどいい最小構成**

---

## ④ CodeBuildRoleのポイント

* ECR（必須）
* S3（artifact）
* Logs
* EKS Describe

👉 CI/CDに必要最低限

---

# ⚠️ 実務での強化ポイント（後でやる）

* Resource `"*"` → 制限
* ECR repo限定
* S3 bucket限定
* AssumeRole条件（MFAなど）

---

# 👍 まとめ

この構成で👇が成立

* 完全Private EKS構築
* 安全なロールスイッチ
* CodeBuild CI/CD
* kubectl操作（Bastion & CodeBuild）

---
---
