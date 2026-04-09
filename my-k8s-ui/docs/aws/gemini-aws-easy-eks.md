おっしゃる通り、現状ですでにSSMログインができているのであれば、既存のIAMロール（以下「既存ロール」）がすでにEC2にアタッチされています。

CloudFormation（CFn）で管理する場合、**「既存のロールを上書きする」のではなく、「既存の構成をCFnの管理下に置く（インポートする）」か「新しいロールを作って差し替える」**かのどちらかになります。

運用上の安全性を考えると、以下の**「共存・差し替え型」**のテンプレートが最もスムーズです。

---

## 既存環境を活かすための戦略

1.  **既存ロールはそのまま**: 現在のSSMログイン環境を壊さないよう、既存ロールには手を触れません。
2.  **作業用ロールとAccess Entryを新規作成**: スイッチ先の強い権限（EKS操作用）をCFnで作ります。
3.  **既存ロールへの「許可」だけ手動追加**: 既存ロールが「作業用ロール」にスイッチできるよう、既存ロールのポリシーに `sts:AssumeRole` を1件だけ追加します。

### 推奨：作業用権限セット（CFnテンプレート）

このテンプレートは、既存の踏み台ロールのARNを「パラメータ」として受け取り、それに対してスイッチを許可する構成です。

```yaml
AWSTemplateFormatVersion: '2010-09-09'
Description: EKS Work Execution Role and Access Entry (Assuming Bastion Role already exists)

Parameters:
  EKSClusterName:
    Type: String
    Description: Name of your EKS Cluster.
  ExistingBastionRoleArn:
    Type: String
    Description: ARN of the existing Bastion IAM Role (e.g., arn:aws:iam::123456789012:role/ExistingBastionRole)

Resources:
  # ------------------------------------------------------------
  # 1. スイッチ先（作業用）IAMロール
  # ------------------------------------------------------------
  WorkExecutionRole:
    Type: AWS::IAM::Role
    Properties:
      RoleName: !Sub "${AWS::StackName}-WorkExecutionRole"
      AssumeRolePolicyDocument:
        Version: '2012-10-17'
        Statement:
          - Effect: Allow
            Principal:
              # ここで「既存の踏み台ロール」からのスイッチを許可する
              AWS: !Ref ExistingBastionRoleArn
            Action: sts:AssumeRole
      ManagedPolicyArns:
        - arn:aws:iam::aws:policy/AmazonEKSClusterPolicy
        - arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryFullAccess
        - arn:aws:iam::aws:policy/CloudFormationFullAccess
        - arn:aws:iam::aws:policy/AmazonSSMFullAccess

  # ------------------------------------------------------------
  # 2. EKS Access Entry (AmazonEKSClusterAdminPolicy)
  # ------------------------------------------------------------
  WorkRoleAccessEntry:
    Type: AWS::EKS::AccessEntry
    Properties:
      ClusterName: !Ref EKSClusterName
      PrincipalArn: !GetAtt WorkExecutionRole.Arn
      Type: STANDARD

  AdminPolicyAssociation:
    Type: AWS::EKS::AccessPolicyAssociation
    Properties:
      ClusterName: !Ref EKSClusterName
      PrincipalArn: !GetAtt WorkExecutionRole.Arn
      PolicyArn: arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy
      AccessScope:
        Type: cluster

Outputs:
  WorkExecutionRoleArn:
    Description: Copy this ARN to your bastion's AWS config
    Value: !GetAtt WorkExecutionRole.Arn
```

---

## 導入後の仕上げ作業（2ステップ）

テンプレートをデプロイした後、以下の2点だけ対応してください。

### ステップ1：既存ロールに「スイッチ許可」を足す
AWSコンソール等で、現在EC2に付いている**既存ロール**を開き、以下のインラインポリシーを追加してください。これをしないと、踏み台から `aws sts assume-role` を叩いた時に拒否されます。

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": "sts:AssumeRole",
            "Resource": "arn:aws:iam::[アカウントID]:role/[作成されたWorkExecutionRoleの名]"
        }
    ]
}
```

### ステップ2：踏み台でのプロファイル作成
SSMでログインし、新しく作ったロールを使う設定を入れます。

```bash
aws configure set profile.eks-work.role_arn [作成されたWorkExecutionRoleのARN]
aws configure set profile.eks-work.credential_source Ec2InstanceMetadata
```

### 補足：なぜ「上書き」しないのか？
既存のロールをCFnで管理していない場合、同じ名前でCFnから作ろうとすると「Resource already exists」というエラーで止まります。
