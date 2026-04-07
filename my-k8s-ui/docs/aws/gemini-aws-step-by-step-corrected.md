踏み台EC2のIAMロールでデプロイを行う前提に基づき、デプロイ用ロールの定義は除外しています。

---

## 🧱 Step 0: Foundation (VPC & EKS Base)
完全閉域環境でEKSを安定稼働させるための決定版テンプレートです。

### 📄 step0-foundation.yaml
```yaml
AWSTemplateFormatVersion: '2010-09-09'
Description: Full Private EKS Foundation with corrected Endpoints and Tags

Parameters:
  ClusterName:
    Type: String
    Default: my-eks
  VPCId:
    Type: AWS::EC2::VPC::Id
  RouteTableId:
    Type: String

Resources:
# ------------------------
# Subnets (Private Only + Required Tags)
# ------------------------
  PrivateSubnetA:
    Type: AWS::EC2::Subnet
    Properties:
      VpcId: !Ref VPCId
      CidrBlock: 10.0.1.0/24
      AvailabilityZone: !Sub "${AWS::Region}a"
      Tags:
        - Key: Name
          Value: !Sub "${ClusterName}-subnet-a"
        - Key: "kubernetes.io/role/internal-elb" # ALB Controller用
          Value: "1"
        - Key: "karpenter.sh/discovery" # Karpenter用
          Value: !Ref ClusterName

  PrivateSubnetB:
    Type: AWS::EC2::Subnet
    Properties:
      VpcId: !Ref VPCId
      CidrBlock: 10.0.2.0/24
      AvailabilityZone: !Sub "${AWS::Region}c"
      Tags:
        - Key: Name
          Value: !Sub "${ClusterName}-subnet-b"
        - Key: "kubernetes.io/role/internal-elb"
          Value: "1"
        - Key: "karpenter.sh/discovery"
          Value: !Ref ClusterName

# ------------------------
# Security Group (Self-Referencing)
# ------------------------
  EKSSG:
    Type: AWS::EC2::SecurityGroup
    Properties:
      GroupDescription: EKS and Endpoint SG
      VpcId: !Ref VPCId
      SecurityGroupIngress:
        - IpProtocol: -1
          FromPort: -1
          ToPort: -1
          SourceSecurityGroupId: !Ref EKSSG # SG自身からの通信を許可（循環参照）
        - IpProtocol: tcp
          FromPort: 443
          ToPort: 443
          CidrIp: 10.0.0.0/16 # VPC内からのHTTPSを許可

# ------------------------
# IAM Roles (Cluster & Node)
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
        - arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore # 踏み台・Nodeログイン用

# ------------------------
# EKS Cluster (Private Endpoint)
# ------------------------
  EKSCluster:
    Type: AWS::EKS::Cluster
    Properties:
      Name: !Ref ClusterName
      RoleArn: !GetAtt EKSClusterRole.Arn
      ResourcesVpcConfig:
        SubnetIds: [!Ref PrivateSubnetA, !Ref PrivateSubnetB]
        EndpointPrivateAccess: true # Privateのみ
        EndpointPublicAccess: false
        SecurityGroupIds: [!Ref EKSSG]

  NodeGroup:
    Type: AWS::EKS::Nodegroup
    DependsOn: EKSCluster
    Properties:
      ClusterName: !Ref ClusterName
      NodeRole: !GetAtt NodeRole.Arn
      Subnets: [!Ref PrivateSubnetA, !Ref PrivateSubnetB]
      ScalingConfig:
        DesiredSize: 2
        MinSize: 1
        MaxSize: 3
      InstanceTypes: [t3.medium]

# ------------------------
# VPC Endpoints (Full Private Support)
# ------------------------
  # S3 (Gateway)
  S3Endpoint:
    Type: AWS::EC2::VPCEndpoint
    Properties:
      VpcId: !Ref VPCId
      ServiceName: !Sub "com.amazonaws.${AWS::Region}.s3"
      VpcEndpointType: Gateway
      RouteTableIds: [!Ref RouteTableId]

  # Interface Endpoints (Required for EKS/ALB/SSM)
  ECRAPI:
    Type: AWS::EC2::VPCEndpoint
    Properties:
      VpcId: !Ref VPCId
      ServiceName: !Sub "com.amazonaws.${AWS::Region}.ecr.api"
      VpcEndpointType: Interface
      SubnetIds: [!Ref PrivateSubnetA, !Ref PrivateSubnetB]
      SecurityGroupIds: [!Ref EKSSG]

  ECRDKR:
    Type: AWS::EC2::VPCEndpoint
    Properties:
      VpcId: !Ref VPCId
      ServiceName: !Sub "com.amazonaws.${AWS::Region}.ecr.dkr"
      VpcEndpointType: Interface
      SubnetIds: [!Ref PrivateSubnetA, !Ref PrivateSubnetB]
      SecurityGroupIds: [!Ref EKSSG]

  STS:
    Type: AWS::EC2::VPCEndpoint
    Properties:
      VpcId: !Ref VPCId
      ServiceName: !Sub "com.amazonaws.${AWS::Region}.sts"
      VpcEndpointType: Interface
      SubnetIds: [!Ref PrivateSubnetA, !Ref PrivateSubnetB]
      SecurityGroupIds: [!Ref EKSSG]

  # 追加分: EC2 API (Karpenter/ALB用)
  EC2:
    Type: AWS::EC2::VPCEndpoint
    Properties:
      VpcId: !Ref VPCId
      ServiceName: !Sub "com.amazonaws.${AWS::Region}.ec2"
      VpcEndpointType: Interface
      SubnetIds: [!Ref PrivateSubnetA, !Ref PrivateSubnetB]
      SecurityGroupIds: [!Ref EKSSG]

  # 追加分: EKS API (Node通信用)
  EKS:
    Type: AWS::EC2::VPCEndpoint
    Properties:
      VpcId: !Ref VPCId
      ServiceName: !Sub "com.amazonaws.${AWS::Region}.eks"
      VpcEndpointType: Interface
      SubnetIds: [!Ref PrivateSubnetA, !Ref PrivateSubnetB]
      SecurityGroupIds: [!Ref EKSSG]

  # 追加分: ELB API (ALB Controller用)
  ELB:
    Type: AWS::EC2::VPCEndpoint
    Properties:
      VpcId: !Ref VPCId
      ServiceName: !Sub "com.amazonaws.${AWS::Region}.elasticloadbalancing"
      VpcEndpointType: Interface
      SubnetIds: [!Ref PrivateSubnetA, !Ref PrivateSubnetB]
      SecurityGroupIds: [!Ref EKSSG]

  # 追加分: CloudWatch Logs (Logging用)
  Logs:
    Type: AWS::EC2::VPCEndpoint
    Properties:
      VpcId: !Ref VPCId
      ServiceName: !Sub "com.amazonaws.${AWS::Region}.logs"
      VpcEndpointType: Interface
      SubnetIds: [!Ref PrivateSubnetA, !Ref PrivateSubnetB]
      SecurityGroupIds: [!Ref EKSSG]

Outputs:
  ClusterName:
    Value: !Ref ClusterName
  EKSSG:
    Value: !Ref EKSSG
```

---

## ☸️ Step 1: Pod Identity Agent の有効化
EKSクラスター作成後、Pod Identityを使用するためにアドオンをインストールします。

```bash
# アドオンのインストール
aws eks create-addon \
  --cluster-name my-eks \
  --addon-name eks-pod-identity-agent
```

---

## ⚡ Step 3: Karpenter (Pod Identity版修正)
KarpenterのNodePoolで、Step 0で付与したタグを使用してサブネットを自動検出するようにします。

### 📄 step3-karpenter-iam.yaml (修正なし)
※元ファイルの `sts:AssumeRole` と `Principal: pods.eks.amazonaws.com` の組み合わせで問題ありません。

### 🧩 NodePool 設定 (修正版)
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
          values: ["t3.medium", "t3.large"]
        - key: "topology.kubernetes.io/zone"
          operator: In
          values: ["ap-northeast-1a", "ap-northeast-1c"]
      nodeClassRef:
        name: default
---
apiVersion: karpenter.sh/v1beta1
kind: EC2NodeClass
metadata:
  name: default
spec:
  amiFamily: AL2
  role: "my-eks-node-role" # Step 0で作ったNodeRole名
  subnetSelectorTerms:
    - tags:
        karpenter.sh/discovery: "my-eks" # Step 0のタグと一致させる
  securityGroupSelectorTerms:
    - tags:
        aws:cloudformation:stack-name: "foundation" # SGを自動検出
```

---

## 🌐 Step 4: AWS Load Balancer Controller
こちらもアドオンと同様に、Pod Identityを利用して権限を付与します。

```bash
# IAM Role作成 (step4-alb-iam.yamlを使用)
# Association作成
aws eks create-pod-identity-association \
  --cluster-name my-eks \
  --namespace kube-system \
  --service-account aws-load-balancer-controller \
  --role-arn arn:aws:iam::${ACCOUNT_ID}:role/my-eks-alb-role

# Helmでインストール
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=my-eks \
  --set vpcId=vpc-xxxxxx \
  --set region=ap-northeast-1
```

これで、NAT Gatewayなしの完全閉域環境において、各種コントローラーがAWS APIと正しく通信し、リソースの自動作成・スケーリングができる構成が整います。

---
---

## 🌐 1. 必要となるVPCエンドポイント

踏み台EC2からCLIでデプロイを完結させるには、以下のエンドポイントが追加で必要になります。

### クライアント（踏み台）がCLIを実行するために必要
* **`com.amazonaws.[region].cloudformation` (Interface)**:
    これがないと、`aws cloudformation deploy` コマンドがAWSサービスに到達できずタイムアウトします。

### スタックの内容（EKS作成等）を正常に完了させるために必要
CloudFormationはAWSの内部ネットワークを通じてリソースを作成しますが、**EKSクラスターが立ち上がった後の初期化（ノードの参加やアドオンの確認）**において、VPC内部からの通信が発生します。
* **`com.amazonaws.[region].eks` (Interface)**: EKSのAPI操作に必要です。
* **`com.amazonaws.[region].ec2` (Interface)**: サブネットやセキュリティグループ、ノードグループ（EC2）の構築・確認に必要です。

---

## 🔐 2. デプロイ時に踏み台EC2に必要となるIAMロール

踏み台EC2に割り当てるIAMロール（インスタンスプロファイル）には、**「スタックに含まれるすべてのリソースを作成・管理・削除できる権限」**が必要です。

### 必要な権限セット（インラインポリシー等）
最低限、以下の権限をまとめたロールを作成し、踏み台に付与してください。

| サービス | 必要なアクション例 | 用途 |
| :--- | :--- | :--- |
| **CloudFormation** | `CreateStack`, `UpdateStack`, `DeleteStack`, `DescribeStacks` | スタック自体の操作 |
| **EC2** | `CreateVpc`, `CreateSubnet`, `CreateSecurityGroup`, `RunInstances` | ネットワークとノードの構築 |
| **IAM** | `CreateRole`, `PutRolePolicy`, **`PassRole`** | EKSやノード用のロール作成と割り当て |
| **EKS** | `CreateCluster`, `DescribeCluster`, `CreateNodegroup` | EKS本体とノードグループの構築 |

> [!IMPORTANT]
> **`iam:PassRole` 権限について**
> CloudFormationが「EKSクラスターロール」や「ノードロール」を作成し、それを各リソースに引き渡す（Pass）ために、デプロイを実行するロールには `iam:PassRole` 権限が明示的に必要です。

---

## 🛠 修正版：Step 0 へのエンドポイント追加

前回の `step0-foundation.yaml` に、CloudFormation自体のエンドポイントを追加した最終的な構成案です。

```yaml
# ... (前回のテンプレートのResourcesセクションに追加)

  CloudFormationEndpoint:
    Type: AWS::EC2::VPCEndpoint
    Properties:
      VpcId: !Ref VPCId
      ServiceName: !Sub "com.amazonaws.${AWS::Region}.cloudformation"
      VpcEndpointType: Interface
      SubnetIds: [!Ref PrivateSubnetA, !Ref PrivateSubnetB]
      SecurityGroupIds: [!Ref EKSSG]

# ...
```

### まとめ
1.  **VPCエンドポイント**: `cloudformation` 用のエンドポイントは**必須**です（CLIを通すため）。
2.  **IAMロール**: 踏み台EC2のロールには、各リソース（EC2, EKS, IAM）の作成権限に加えて、**`iam:PassRole`** が付いていることを確認してください。

これで、外部との通信を一切遮断した状態で、踏み台からインフラをコードで管理する準備が整います。
