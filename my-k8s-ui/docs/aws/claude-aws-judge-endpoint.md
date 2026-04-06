### ディレクトリ構成

```
cfn/
├── stack-endpoints.yaml   # エンドポイント専用スタック
├── stack-service.yaml     # サービス本体スタック
└── deploy.sh              # デプロイスクリプト
```

---

### stack-endpoints.yaml

```yaml
AWSTemplateFormatVersion: "2010-09-09"
Description: VPC Endpoints Stack

Parameters:
  VpcId:
    Type: AWS::EC2::VPC::Id
  RouteTableIds:
    Type: CommaDelimitedList
  SubnetIds:
    Type: CommaDelimitedList
  EndpointSecurityGroupId:
    Type: AWS::EC2::SecurityGroup::Id

Resources:
  # S3 (Gateway型)
  S3Endpoint:
    Type: AWS::EC2::VPCEndpoint
    Properties:
      VpcId: !Ref VpcId
      ServiceName: !Sub "com.amazonaws.${AWS::Region}.s3"
      VpcEndpointType: Gateway
      RouteTableIds: !Ref RouteTableIds

  # SSM (Interface型)
  SSMEndpoint:
    Type: AWS::EC2::VPCEndpoint
    Properties:
      VpcId: !Ref VpcId
      ServiceName: !Sub "com.amazonaws.${AWS::Region}.ssm"
      VpcEndpointType: Interface
      SubnetIds: !Ref SubnetIds
      SecurityGroupIds: [!Ref EndpointSecurityGroupId]
      PrivateDnsEnabled: true

  SsmMessagesEndpoint:
    Type: AWS::EC2::VPCEndpoint
    Properties:
      VpcId: !Ref VpcId
      ServiceName: !Sub "com.amazonaws.${AWS::Region}.ssmmessages"
      VpcEndpointType: Interface
      SubnetIds: !Ref SubnetIds
      SecurityGroupIds: [!Ref EndpointSecurityGroupId]
      PrivateDnsEnabled: true

  # STS (Interface型)
  STSEndpoint:
    Type: AWS::EC2::VPCEndpoint
    Properties:
      VpcId: !Ref VpcId
      ServiceName: !Sub "com.amazonaws.${AWS::Region}.sts"
      VpcEndpointType: Interface
      SubnetIds: !Ref SubnetIds
      SecurityGroupIds: [!Ref EndpointSecurityGroupId]
      PrivateDnsEnabled: true

  # CloudWatch Logs (Interface型)
  CloudWatchLogsEndpoint:
    Type: AWS::EC2::VPCEndpoint
    Properties:
      VpcId: !Ref VpcId
      ServiceName: !Sub "com.amazonaws.${AWS::Region}.logs"
      VpcEndpointType: Interface
      SubnetIds: !Ref SubnetIds
      SecurityGroupIds: [!Ref EndpointSecurityGroupId]
      PrivateDnsEnabled: true

  # CFn (Interface型) ← CFnデプロイ自体に必要
  CloudFormationEndpoint:
    Type: AWS::EC2::VPCEndpoint
    Properties:
      VpcId: !Ref VpcId
      ServiceName: !Sub "com.amazonaws.${AWS::Region}.cloudformation"
      VpcEndpointType: Interface
      SubnetIds: !Ref SubnetIds
      SecurityGroupIds: [!Ref EndpointSecurityGroupId]
      PrivateDnsEnabled: true

  # ── SSMパラメータに登録 ──────────────────────────
  ParamS3Endpoint:
    Type: AWS::SSM::Parameter
    Properties:
      Name: /myapp/vpc/endpoint/s3
      Type: String
      Value: !Ref S3Endpoint

  ParamSSMEndpoint:
    Type: AWS::SSM::Parameter
    Properties:
      Name: /myapp/vpc/endpoint/ssm
      Type: String
      Value: !Ref SSMEndpoint

  ParamSTSEndpoint:
    Type: AWS::SSM::Parameter
    Properties:
      Name: /myapp/vpc/endpoint/sts
      Type: String
      Value: !Ref STSEndpoint

  ParamCWLogsEndpoint:
    Type: AWS::SSM::Parameter
    Properties:
      Name: /myapp/vpc/endpoint/logs
      Type: String
      Value: !Ref CloudWatchLogsEndpoint

Outputs:
  S3EndpointId:
    Value: !Ref S3Endpoint
    Export:
      Name: !Sub "${AWS::StackName}-S3EndpointId"

  STSEndpointId:
    Value: !Ref STSEndpoint
    Export:
      Name: !Sub "${AWS::StackName}-STSEndpointId"
```

---

### stack-service.yaml

```yaml
AWSTemplateFormatVersion: "2010-09-09"
Description: Service Stack

Parameters:
  VpcId:
    Type: AWS::EC2::VPC::Id
  SubnetIds:
    Type: CommaDelimitedList

  # ② エンドポイントを作るかどうか（手動作成済みならfalse）
  CreateVpcEndpoints:
    Type: String
    Default: "false"
    AllowedValues: ["true", "false"]
    Description: "手動作成済みの場合はfalse"

  # 手動作成済みエンドポイントのIDを外から渡す用（CreateVpcEndpoints=falseの時に使用）
  ExistingS3EndpointId:
    Type: String
    Default: ""
  ExistingSTSEndpointId:
    Type: String
    Default: ""

Conditions:
  ShouldCreateEndpoints: !Equals [!Ref CreateVpcEndpoints, "true"]
  # SSMにエンドポイントIDが登録済みかを判定（手動作成時はSSM登録も手動前提）
  UseExistingEndpoints: !Equals [!Ref CreateVpcEndpoints, "false"]

Resources:
  # ── エンドポイント（未作成の場合のみ） ──────────────
  S3Endpoint:
    Type: AWS::EC2::VPCEndpoint
    Condition: ShouldCreateEndpoints
    Properties:
      VpcId: !Ref VpcId
      ServiceName: !Sub "com.amazonaws.${AWS::Region}.s3"
      VpcEndpointType: Gateway
      RouteTableIds:
        - !Ref ServiceRouteTable

  STSEndpoint:
    Type: AWS::EC2::VPCEndpoint
    Condition: ShouldCreateEndpoints
    Properties:
      VpcId: !Ref VpcId
      ServiceName: !Sub "com.amazonaws.${AWS::Region}.sts"
      VpcEndpointType: Interface
      SubnetIds: !Ref SubnetIds
      PrivateDnsEnabled: true

  # ── サービス本体リソース ──────────────────────────
  ServiceRouteTable:
    Type: AWS::EC2::RouteTable
    Properties:
      VpcId: !Ref VpcId

  MyECSTaskRole:
    Type: AWS::IAM::Role
    Properties:
      AssumeRolePolicyDocument:
        Version: "2012-10-17"
        Statement:
          - Effect: Allow
            Principal: {Service: ecs-tasks.amazonaws.com}
            Action: sts:AssumeRole
      ManagedPolicyArns:
        - arn:aws:iam::aws:policy/CloudWatchLogsFullAccess

  MyLogGroup:
    Type: AWS::Logs::LogGroup
    Properties:
      # ③ SSM経由でエンドポイントIDを参照（手動作成済みでもSSMに登録されていれば参照可能）
      # ※ LogGroupはエンドポイントIDを直接使わないが、
      #    他のリソースでSSM参照する例として下に示す
      LogGroupName: /myapp/service
      RetentionInDays: 30

  # SSMパラメータ経由でエンドポイントIDを参照する例（例：カスタムリソースや他サービスへの受け渡し）
  ParamUsedEndpointS3:
    Type: AWS::SSM::Parameter
    Properties:
      Name: /myapp/service/using-s3-endpoint
      Type: String
      # 作成した場合は!Ref、既存の場合はSSM resolveで取得
      Value: !If
        - ShouldCreateEndpoints
        - !Ref S3Endpoint
        - "{{resolve:ssm:/myapp/vpc/endpoint/s3}}"

Outputs:
  UsedS3EndpointId:
    Value: !If
      - ShouldCreateEndpoints
      - !Ref S3Endpoint
      - "{{resolve:ssm:/myapp/vpc/endpoint/s3}}"
```

---

### deploy.sh

```bash
#!/bin/bash
set -e

STACK_ENDPOINTS="myapp-endpoints"
STACK_SERVICE="myapp-service"
VPC_ID="vpc-xxxxxxxxxxxxxxxxx"
SUBNET_IDS="subnet-aaa,subnet-bbb"
SG_ID="sg-xxxxxxxxxxxxxxxxx"
ROUTE_TABLE_IDS="rtb-xxxxxxxxxxxxxxxxx"
REGION="ap-northeast-1"

# ── エンドポイントスタックが既存か確認 ──────────────
ENDPOINT_STACK_EXISTS=$(aws cloudformation describe-stacks \
  --stack-name "$STACK_ENDPOINTS" \
  --region "$REGION" \
  --query "Stacks[0].StackStatus" \
  --output text 2>/dev/null || echo "NOT_EXIST")

if [ "$ENDPOINT_STACK_EXISTS" = "NOT_EXIST" ]; then
  echo ">>> エンドポイントスタックが存在しないため確認..."

  # 手動作成済みエンドポイントがあるか確認
  EXISTING_S3=$(aws ec2 describe-vpc-endpoints \
    --filters "Name=vpc-id,Values=$VPC_ID" \
              "Name=service-name,Values=com.amazonaws.${REGION}.s3" \
              "Name=state,Values=available" \
    --query "VpcEndpoints[0].VpcEndpointId" \
    --output text 2>/dev/null || echo "None")

  if [ "$EXISTING_S3" = "None" ] || [ "$EXISTING_S3" = "" ]; then
    echo ">>> 手動エンドポイントなし → エンドポイントスタックをデプロイ"
    aws cloudformation deploy \
      --stack-name "$STACK_ENDPOINTS" \
      --template-file cfn/stack-endpoints.yaml \
      --region "$REGION" \
      --parameter-overrides \
        VpcId="$VPC_ID" \
        SubnetIds="$SUBNET_IDS" \
        EndpointSecurityGroupId="$SG_ID" \
        RouteTableIds="$ROUTE_TABLE_IDS"
    CREATE_ENDPOINTS="false"  # スタックが作ったのでserviceスタックは作らなくていい
  else
    echo ">>> 手動エンドポイントあり (ID: $EXISTING_S3) → SSMに手動登録"
    # 手動作成済みエンドポイントIDをSSMに登録しておく
    aws ssm put-parameter \
      --name "/myapp/vpc/endpoint/s3" \
      --value "$EXISTING_S3" \
      --type String \
      --overwrite \
      --region "$REGION"
    CREATE_ENDPOINTS="false"
  fi
else
  echo ">>> エンドポイントスタック既存 → スキップ"
  CREATE_ENDPOINTS="false"
fi

# ── サービススタックのデプロイ ──────────────────────
echo ">>> サービススタックをデプロイ (CreateVpcEndpoints=$CREATE_ENDPOINTS)"
aws cloudformation deploy \
  --stack-name "$STACK_SERVICE" \
  --template-file cfn/stack-service.yaml \
  --region "$REGION" \
  --capabilities CAPABILITY_IAM \
  --parameter-overrides \
    VpcId="$VPC_ID" \
    SubnetIds="$SUBNET_IDS" \
    CreateVpcEndpoints="$CREATE_ENDPOINTS"

echo ">>> デプロイ完了"
```

---

### ポイントまとめ

```
判定フロー
──────────────────────────────────────────────────────
手動作成済み？
  YES → deploy.sh が SSM にエンドポイントIDを put-parameter
         → service stack は resolve:ssm で参照
  NO  → endpoint stack をデプロイ（SSMへの登録もstack内で行う）
         → service stack は同じく resolve:ssm で参照

service stack から見れば常に resolve:ssm で統一参照できる
```

`resolve:ssm` で参照を統一することで、**エンドポイントがCFn管理でも手動作成でも、serviceスタック側のテンプレートは変更不要**になるのがこの構成の肝です。

---

## 実際にやっていること

上記の `deploy.sh` では **S3エンドポイントの有無だけをサンプルとして確認**しているだけで、「S3があれば他も全部あるだろう」という**雑な前提**になっています。

---

## SSM経由での踏み台EC2に必要なエンドポイント一覧

正確にチェックすべきはこれらです。

```
Interface型
├── com.amazonaws.{region}.ssm
├── com.amazonaws.{region}.ssmmessages
├── com.amazonaws.{region}.ec2messages
├── com.amazonaws.{region}.sts          ← IAMロール利用時
└── com.amazonaws.{region}.logs         ← CloudWatch Logs

Gateway型
└── com.amazonaws.{region}.s3           ← CFnテンプレートのS3取得など
```

---

## deploy.sh を正しく直すなら

```bash
# チェックすべきエンドポイント一覧
REQUIRED_ENDPOINTS=(
  "com.amazonaws.${REGION}.ssm"
  "com.amazonaws.${REGION}.ssmmessages"
  "com.amazonaws.${REGION}.ec2messages"
  "com.amazonaws.${REGION}.sts"
  "com.amazonaws.${REGION}.logs"
  "com.amazonaws.${REGION}.s3"
)

ALL_EXIST=true

for SERVICE in "${REQUIRED_ENDPOINTS[@]}"; do
  RESULT=$(aws ec2 describe-vpc-endpoints \
    --filters "Name=vpc-id,Values=$VPC_ID" \
              "Name=service-name,Values=$SERVICE" \
              "Name=state,Values=available" \
    --query "VpcEndpoints[0].VpcEndpointId" \
    --output text 2>/dev/null)

  if [ "$RESULT" = "None" ] || [ -z "$RESULT" ]; then
    echo ">>> 未作成: $SERVICE"
    ALL_EXIST=false
  else
    echo ">>> 確認済み: $SERVICE ($RESULT)"
  fi
done

if [ "$ALL_EXIST" = "true" ]; then
  echo ">>> 全エンドポイント手動作成済み → エンドポイントスタックはスキップ"
  CREATE_ENDPOINTS="false"
else
  echo ">>> 未作成エンドポイントあり → エンドポイントスタックをデプロイ"
  CREATE_ENDPOINTS="true"
fi
```

---

## ただし注意点

一部だけ手動作成済みで残りが未作成、という**中途半端な状態**だと上記でも破綻します。その場合は

- 全部手動作成に統一する
- 全部CFnスタックに統一する（手動作成済みのものを先に削除）

どちらかに**割り切ることが実運用では重要**です。

---

## SSM経由踏み台EC2（完全Private）に必要なエンドポイント

### 必須（これがないとSSMセッション自体が繋がらない）

```
com.amazonaws.{region}.ssm
com.amazonaws.{region}.ssmmessages
com.amazonaws.{region}.ec2messages
```

### 実質必須（EC2起動・運用で必要）

```
com.amazonaws.{region}.ec2          ← EC2 API
com.amazonaws.{region}.sts          ← IAMロールの認証情報取得
```

### CFnで構築作業するなら追加で必須

```
com.amazonaws.{region}.cloudformation   ← CFn API
com.amazonaws.{region}.s3              ← CFnテンプレート/パッケージのS3取得 (Gateway型)
```

### ログ・監視を使うなら

```
com.amazonaws.{region}.logs             ← CloudWatch Logs
com.amazonaws.{region}.monitoring       ← CloudWatch Metrics (任意)
```

---

### まとめ表

| エンドポイント | 型 | 用途 | 優先度 |
|---|---|---|---|
| ssm | Interface | SSMセッション制御 | 必須 |
| ssmmessages | Interface | SSMセッションデータ転送 | 必須 |
| ec2messages | Interface | SSM Agentとの通信 | 必須 |
| ec2 | Interface | EC2 API | 実質必須 |
| sts | Interface | IAMロール認証 | 実質必須 |
| cloudformation | Interface | CFn API | CFn作業時必須 |
| s3 | Gateway | テンプレート取得 | CFn作業時必須 |
| logs | Interface | CloudWatch Logs | ログ使用時必須 |
| monitoring | Interface | CloudWatch Metrics | 任意 |

---

### 補足

**`ec2messages` は意外と見落とされがち**ですが、SSM AgentがEC2 Messageサービス経由で通信するため、これがないとセッションが途中で切れたり不安定になります。

**S3はGateway型**なのでインターフェース型と設定方法が異なり（ルートテーブルへの関連付けが必要）、セキュリティグループも不要な点も注意です。
