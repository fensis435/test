| パターン | リソース | 何が問題か | 対処 |
|---|---|---|---|
| A: 完全リスト管理 | S3 Gateway Endpoint | `RouteTableIds`は差分でなく全リスト。新規RTB追加のたびに再デプロイ必須 | RTB粒度を減らす／SSM StringListで一元管理 |
| A: 完全リスト管理 | DynamoDB Gateway Endpoint | S3と同様の構造 | 同上 |
| A: 完全リスト管理 | Security Group 自己参照ルール | インラインルールで自己参照すると循環依存でデプロイ失敗 | `AWS::EC2::SecurityGroupIngress`を別リソースに分離 |
| B: 明示的許可 | Interface VPC Endpoint (ecr.api等) | ポリシーを絞ると、API呼び出し追加のたびにポリシー更新が必要 | 許可範囲は広めに設計するか変更頻度を見込んでおく |
| B: 明示的許可 | KMS Key Policy | IAM PolicyとKey Policyの両方がAllowでないとアクセス不可(ダブルゲート) | 新規ロール追加時はKey Policy更新をセットで運用手順化 |
| B: 明示的許可 | ECR リポジトリポリシー | マルチテナント/マルチクラスタでpullする場合、許可プリンシパルの完全リスト管理が必要 | テナント追加時のポリシー更新をIaC化・自動化 |
| C: 双方向更新 | VPC Peering ルートテーブル | 双方のVPCでルートテーブル追加が必要。片側だけだと疎通しない | クロスアカウントはSSM/RAM共有+手動調整を前提に設計 |
| C: 双方向更新 | Transit Gateway | アタッチメント・TGWルートテーブル関連付け・伝播設定の4層構造 | 新規VPC接続時のチェックリスト化 |
| C: 双方向更新 | Route53 Private Hosted Zone VPC Association | クロスアカウントだと相手側の認可(Authorization)と自側の関連付け(Association)のペアが必要 | CLI併用を前提にランブック化 |
| D: EKS特有 | EFS マウントターゲット用SG | 新規AZ/サブネット追加のたびにNFS(2049)許可ルールの追加が必要 | AZ追加時のチェックリストに組み込む |
| D: EKS特有 | Karpenter discoveryタグ | タグ付け漏れがあってもCFnはエラーを出さず、ノード起動失敗で初めて気づく | タグ付けをテンプレートの標準セットとして固定化 |
| D: EKS特有 | IRSA OIDC Provider Thumbprint | 証明書更新に古いThumbprintが追従できていないケースがある | 定期的な値の見直し・監視 |

**共通の見分け方**として、プロパティが単一IDでなく**リスト型**になっているもの、または**2つの独立リソース/アカウントの両方**を更新しないと機能しないものは要注意、という軸でまとめてあります。

---
---

以下、各リソースについて「具体的に何が起きるか」「なぜそうなるか」「どう防ぐか」を順に説明します。長くなるので、パターンごとに区切ります。

---

## パターンA: 完全リストで管理する系

### 1. S3 Gateway Endpoint

**具体例:**
最初にプライベートサブネットを2つ(AZ-a, AZ-c)作り、それぞれにルートテーブルRTB-a, RTB-cを用意して、S3 Endpointの`RouteTableIds`に両方登録したとします。

```yaml
RouteTableIds:
  - !Ref RTB_a
  - !Ref RTB_c
```

半年後、AZ-dにEKSノードグループを追加することになり、新しいサブネットとルートテーブルRTB-dを作成しました。しかしS3 Endpointの`RouteTableIds`を更新するのを忘れると、**AZ-dのPodはS3(ECRのレイヤーpullで内部的に使われることもある)にアクセスできず、コンテナ起動が謎のタイムアウトで失敗する**という形で症状が出ます。エラーメッセージが「S3に繋がらない」と直接言ってくれないので、原因特定に時間がかかりがちです。

**対策:**
一番シンプルなのは、そもそもルートテーブルの数を増やさない設計にすることです。AZごとに個別ルートテーブルを作るのではなく、「プライベートサブラン層」としてルートテーブルを1つ(あるいは環境全体で1〜2個)に共有してしまえば、新しいサブネットを追加してもEndpoint側の変更は不要になります。EKSのワーカーノード用サブネットは基本的に同じルーティングポリシー(NAT不要、VPC内は直接、それ以外はEndpoint経由)で構わないことが多いので、この設計は現実的です。

---

### 2. DynamoDB Gateway Endpoint

**具体例:**
構造はS3と全く同じです。例えばアプリがDynamoDBをセッションストアとして使っている場合、S3と同様に`RouteTableIds`の更新漏れがあると、新しく追加したAZのPodだけDynamoDBへの接続が失敗します。「特定のAZのPodだけエラーになる」という症状が出たら、まずこのEndpointのルートテーブル紐付け漏れを疑ってください。

**対策:**
S3と同じくルートテーブル粒度の設計変更が最優先。すでに個別RTBで運用している場合は、SSM Parameter Store(StringList型)にRTB IDリストを集約しておき、新規RTB作成時にそこへ追記する運用フローをドキュメント化しておくと、少なくとも「忘れる」リスクは減らせます。

---

### 3. Security Group 自己参照ルール(循環依存)

**具体例:**
EKSワーカーノード同士がPod間通信のために、同じSecurity Groupからのトラフィックを許可したいとします。初心者がやりがちなのがこれです。

```yaml
# これはエラーになる
NodeSecurityGroup:
  Type: AWS::EC2::SecurityGroup
  Properties:
    GroupDescription: EKS worker nodes
    SecurityGroupIngress:
      - IpProtocol: -1
        SourceSecurityGroupId: !Ref NodeSecurityGroup  # 自分自身をまだ参照できない
```

CFnはリソースを作成する順番でDAG(依存グラフ)を組みますが、「自分がまだ存在しないのに自分を参照する」形になるため、`Circular dependency between resources`というエラーでデプロイが止まります。

**対策:**
インラインの`SecurityGroupIngress`プロパティではなく、独立したリソースとして後付けする形に分離します。

```yaml
NodeSecurityGroup:
  Type: AWS::EC2::SecurityGroup
  Properties:
    GroupDescription: EKS worker nodes
    # ここにはIngressを書かない

NodeSGIngressSelf:
  Type: AWS::EC2::SecurityGroupIngress
  Properties:
    GroupId: !Ref NodeSecurityGroup
    IpProtocol: -1
    SourceSecurityGroupId: !Ref NodeSecurityGroup
```

こうすると「SG本体を先に作ってから、後でルールを追加する」という2段階の依存関係になり、循環しません。EKSに限らず、「同じSGからの通信を許可したい」というケースは頻出するので、このパターンごと覚えておくと便利です。

---

## パターンB: 明示的な許可がないと機能しない系

### 4. Interface VPC Endpoint のPolicyDocument

**具体例:**
`ecr.api`と`ecr.dkr`のInterface Endpointを作る際、セキュリティを意識して「特定のECRリポジトリのpullだけ許可する」ポリシーを明示的に書いたとします。

```yaml
PolicyDocument:
  Statement:
    - Effect: Allow
      Principal: '*'
      Action: ecr:GetDownloadUrlForLayer
      Resource: 'arn:aws:ecr:ap-northeast-1:123456789012:repository/app-a'
```

後日、新しいマイクロサービス用に`app-b`というリポジトリを追加してpullしようとすると、このEndpointのポリシーに`app-b`のARNが含まれていないため、**`AccessDeniedException`で失敗**します。しかもIAM権限は正しいのに拒否される、というわかりにくい状態になります(EndpointポリシーはIAMとは別レイヤーの許可なので、両方通らないとダメ)。

**対策:**
初心者〜中級者のうちは、Endpointポリシーはデフォルト(フルアクセス)のままにしておくのが安全です。絞り込みは「明確なコンプライアンス要件がある場合」に限定し、絞る場合は新規リポジトリ追加のたびにポリシー更新が必要になることをチームに周知しておきます。

---

### 5. KMS Key Policy(ダブルゲート)

**具体例:**
EKSのSecrets暗号化用にKMSキーを作り、あるIAMロールに`kms:Decrypt`権限をIAM Policyで付与したとします。

```yaml
# IAM側
- Effect: Allow
  Action: kms:Decrypt
  Resource: !GetAtt MyKmsKey.Arn
```

これだけだと**実は復号できません**。KMSキー自体の`KeyPolicy`(リソースベースポリシー)側で、そのIAMロール(またはアカウント)を許可していないと、IAM側でAllowしていてもアクセス拒否になります。これは「IAMとKMS Key Policyの両方が門番として立っている」構造で、初心者が最初に必ずと言っていいほど嵌るポイントです。

```yaml
MyKmsKey:
  Type: AWS::KMS::Key
  Properties:
    KeyPolicy:
      Statement:
        - Sid: AllowRootAccount
          Effect: Allow
          Principal:
            AWS: !Sub 'arn:aws:iam::${AWS::AccountId}:root'
          Action: 'kms:*'
          Resource: '*'
        - Sid: AllowEksRole
          Effect: Allow
          Principal:
            AWS: !GetAtt MyEksRole.Arn
          Action:
            - kms:Decrypt
            - kms:DescribeKey
          Resource: '*'
```

**対策:**
新しいIAMロールにKMS権限を与える際は「IAM Policy側」と「Key Policy側」の両方を必ずセットで確認するチェックリストを作っておくこと。CFnテンプレート上でも、KMSキーを作るスタックとIAMロールを作るスタックが分かれている場合、ロールARNをパラメータ/Exportで渡してKey Policyに動的に追加する設計にしておくと更新漏れを防げます。

---

### 6. ECRリポジトリポリシー(クロスアカウント/クロスクラスタ)

**具体例:**
マルチテナント構成で、共通のベースイメージを格納したECRリポジトリを複数のEKSクラスタ(あるいは複数AWSアカウント)からpullする設計にしたとします。最初はクラスタAのノードロールだけ許可していました。

```yaml
RepositoryPolicyText:
  Statement:
    - Effect: Allow
      Principal:
        AWS: 'arn:aws:iam::111111111111:role/cluster-a-node-role'
      Action:
        - ecr:GetDownloadUrlForLayer
        - ecr:BatchGetImage
```

クラスタBを追加した際にこのポリシーを更新し忘れると、クラスタBのノードだけイメージpullに失敗します。テナントが増えるたびに起きる問題なので、xyzさんのマルチテナント基盤の文脈だと特に注意が必要な箇所です。

**対策:**
テナント(クラスタ)追加のプロビジョニング手順の中に「ECRリポジトリポリシーへのプリンシパル追加」を必須ステップとして組み込み、できればテナント管理用のCFnテンプレート/CI パイプラインの中で自動的にリストへ追記される設計にしておくのが理想です。手作業に依存させないことが最大の対策です。

---

## パターンC: 双方向更新が必要な系

### 7. VPC Peering接続のルートテーブル

**具体例:**
VPC-A(10.0.0.0/16)とVPC-B(10.1.0.0/16)をPeering接続したとします。Peering自体(`AWS::EC2::VPCPeeringConnection`)を作成しただけでは、まだ通信できません。VPC-A側のルートテーブルに「10.1.0.0/16宛はPeering経由」というルートを追加し、**同時にVPC-B側のルートテーブルにも「10.0.0.0/16宛はPeering経由」というルートを追加**する必要があります。

```yaml
# VPC-A側
RouteToVpcB:
  Type: AWS::EC2::Route
  Properties:
    RouteTableId: !Ref VpcARouteTable
    DestinationCidrBlock: 10.1.0.0/16
    VpcPeeringConnectionId: !Ref PeeringConnection

# VPC-B側(別スタック/別アカウントの場合も)
RouteToVpcA:
  Type: AWS::EC2::Route
  Properties:
    RouteTableId: !Ref VpcBRouteTable
    DestinationCidrBlock: 10.0.0.0/16
    VpcPeeringConnectionId: !Ref PeeringConnection
```

片方だけ設定すると「AからBへは繋がるがBからAへの返信パケットが戻ってこない(あるいはその逆)」という、一方向だけ通信できるように見える不可解な状態になります。

**対策:**
Peeringを設定する際は必ず「両側のルートテーブル更新」をワンセットのタスクとして扱うこと。クロスアカウントの場合、CFnの`ImportValue`は同一アカウント内でしか使えないため、相手アカウントのVPC IDやCIDRをSSM Parameter Store経由で共有するか、手動でパラメータ入力する運用にならざるを得ません。ここは素直に「クロスアカウントPeeringは手動連携が前提」とドキュメントに明記しておくのが誠実です。

---

### 8. Transit Gateway(TGW)

**具体例:**
複数VPCを1つのTGWにぶら下げるハブ&スポーク構成を考えます。新しいVPC-Cを追加する際、以下の4つを**すべて**行う必要があります。

1. TGWへのアタッチメント作成(`AWS::EC2::TransitGatewayAttachment`)
2. VPC-C側のルートテーブルに「TGW経由」のルートを追加
3. TGWのルートテーブルに「VPC-Cへのルート」を関連付け(Association)
4. TGWルートテーブルへの伝播設定(Propagation)を有効化

このうち1つでも抜けると、「VPCはTGWに繋がっているように見えるのに、特定の宛先にだけ通信できない」という状態になります。Peeringより層が多い分、抜け漏れのパターンも多くなります。

**対策:**
新規VPC接続時のチェックリストを作り、4項目すべてを機械的に確認する運用にすること。可能であれば、この4点セットをCFnの1つのNested Stack(またはモジュール化したテンプレート)にまとめて「VPCをTGWに繋ぐ」という単位でデプロイできるようにしておくと、手順の抜け漏れそのものを構造的に防げます。

---

### 9. Route53 Private Hosted Zone の VPC Association

**具体例:**
社内用のプライベートDNSゾーン(例: `internal.example.com`)を、複数のVPC(あるいは複数アカウントのVPC)から参照したいとします。同一アカウント内なら`AWS::Route53::HostedZoneVPCAssociation`だけで済みますが、**別アカウントのVPCから参照させたい場合**、まず相手アカウント側で認可(Authorization)を発行してもらう必要があります。

```yaml
# Hosted Zoneを持つアカウント側
VPCAssociationAuthorization:
  Type: AWS::Route53::VPCAssociationAuthorization
  Properties:
    HostedZoneId: !Ref MyHostedZone
    VPCId: other-account-vpc-id
    VPCRegion: ap-northeast-1
```

```yaml
# VPCを持つ別アカウント側(認可された後でないとエラーになる)
HostedZoneAssociation:
  Type: AWS::Route53::HostedZoneVPCAssociation
  Properties:
    HostedZoneId: hosted-zone-id
    VPCId: !Ref MyVPC
```

順番を間違えて先にAssociation側を実行すると、「認可されていない」というエラーで失敗します。

**対策:**
クロスアカウントのDNS共有は、「認可発行 → 紐付け」の順序を厳守すること。CFnだけで完結させようとせず、CLIやランブックで手順を明文化しておくのが現実的です。xyzさんが既にランブック作成に取り組まれているので、この手のクロスアカウント操作は特に手順書化の恩恵が大きい部分だと思います。

---

## パターンD: EKS特有の罠

### 10. EFSマウントターゲット用Security Group

**具体例:**
EFSをPersistent Volumeとして使う場合、EFS本体だけでなく各AZに「マウントターゲット」というENIが作られます。このマウントターゲット用SGで、EKSノードSGからのNFS(ポート2049)を許可していないと、Podからのマウントがタイムアウトします。

```yaml
EfsMountTargetSG:
  Type: AWS::EC2::SecurityGroup
  Properties:
    SecurityGroupIngress:
      - IpProtocol: tcp
        FromPort: 2049
        ToPort: 2049
        SourceSecurityGroupId: !Ref NodeSecurityGroup
```

新しいAZにノードグループを追加したのに、このSGルールの見直しを忘れていた場合、直接的には気づきにくく、「そのAZのPodだけPVCマウントに失敗する」という形で表面化します。

**対策:**
NFSポート許可はソースSGベース(サブネットCIDRではなく)で書いておけば、新しいAZのノードも同じNodeSecurityGroupに属している限り、追加の変更なしで自動的に許可対象に含まれます。むしろこの設計にしておけば、A-9のようにAZ追加のたびに更新が要らなくなるので、最初からこの形で組んでおくのがベストプラクティスです。

---

### 11. Karpenterのdiscoveryタグ

**具体例:**
KarpenterはCFnリソースとしてではなく、**タグを頼りに**「どのサブネットとSecurity Groupを使ってよいか」を実行時に検索します。

```yaml
PrivateSubnetA:
  Type: AWS::EC2::Subnet
  Properties:
    Tags:
      - Key: karpenter.sh/discovery
        Value: my-cluster-name
```

このタグを新しいサブネットに付け忘れても、**CFnのデプロイ自体は成功します**。エラーが出るのはKarpenterがノードをスケールしようとしたタイミングで、「対象のサブネットが見つからない」という形でPodがPending状態のまま止まる、という遅延した症状になります。CFnのエラーとして表面化しないぶん、他の項目より発見が遅れがちです。

**対策:**
サブネット・SGを作成するテンプレートの中で、`karpenter.sh/discovery`タグを他の必須タグ(Name, Environment等)と同列の「標準タグセット」として定義し、リソース作成時に機械的に付与される設計にしておくこと。個別に手で付け忘れる余地をなくすのが最も確実です。

---

### 12. IRSA用 OIDC Provider のThumbprint

**具体例:**
IAM Roles for Service Accounts(IRSA)を使うには、EKSクラスタのOIDC発行者に対応する`AWS::IAM::OIDCProvider`を作り、`ThumbprintList`にルート証明書のフィンガープリントを指定する必要があります。

```yaml
EksOidcProvider:
  Type: AWS::IAM::OIDCProvider
  Properties:
    Url: !GetAtt EksCluster.OpenIdConnectIssuerUrl
    ClientIdList:
      - sts.amazonaws.com
    ThumbprintList:
      - 9e99a48a9960b14926bb7f3b02e22da2b0ab7280  # 古いテンプレートに残りがちな値
```

このThumbprintはAWSが使用するルート証明書のSHA-1フィンガープリントですが、証明書チェーンが将来的に更新されると、古いテンプレートのまま値がハードコードされて残っているケースがあります(現在はAWS側の仕様変更で影響が小さくなっている場合もありますが、テンプレートを使い回していると気づかず古い値のままになりがちです)。

**対策:**
可能であれば`ThumbprintList`をテンプレート内にハードコードせず、参照用のドキュメントやAWS公式のサンプルテンプレートを都度確認する運用にすること。またIRSA関連の権限エラーが出た際は、まずこのThumbprintの妥当性を疑うということをチーム内のトラブルシューティング手順(ランブック)に一言書いておくと、原因特定が早まります。

---

**全体を通じての実務アドバイス**として、これらは共通して「CFnのデプロイ自体は成功するのに、実行時になって初めて問題が発覚する」という性質を持っています。つまり**CFnの構文エラーチェックでは絶対に検出できない**種類の不具合なので、ADR・ランブック・NFRトレーサビリティのドキュメントに、この手の「暗黙の依存関係リスト」を明記しておくことが、実質的な唯一の防御策になります。
