# EKS構築用 踏み台EC2

SSM Session Managerのみでログインする踏み台EC2(Amazon Linux 2023・最新AMI)をCloudFormationで構築します。
操作側の端末は、企業内イントラのUbuntu 24.04(AWS CLI導入済み)を想定しています。
EC2自身の権限は SSM + `sts:AssumeRole` のみで、EKS構築用の広範な権限は
`EksBuilderRole` をassume roleしたときだけ得られます。

## ファイル

| ファイル | 内容 |
|---|---|
| `bastion-ec2.yaml` | CFnテンプレート (VPC任意作成 / VPCエンドポイント / SG / IAM / EC2) |
| `bastion-params.json` | CFnパラメータ (`[{ParameterKey,ParameterValue}]` 形式) |
| `deploy.sh` | スタックが無ければcreate、あればupdate |
| `cleanup.sh` | スタック(=作成物すべて)を削除 |
| `lib/common.sh` | SSOログイン・プロキシ・CFn共通処理 |

## 使い方

```bash
# 操作端末(Ubuntu 24.04)で事前に: sudo apt-get install -y jq  (AWS CLI v2 / Session Manager plugin は導入済み前提)
export HTTPS_PROXY=http://proxy.example.co.jp:8080
export NO_PROXY=localhost,127.0.0.1
# TLSインスペクションがある場合: export AWS_CA_BUNDLE=/path/to/corp-ca.pem

./deploy.sh  -p <sso-profile> -r ap-northeast-1 [-k ~/.ssh/id_ed25519.pub]   # create or update
./cleanup.sh -p <sso-profile> -r ap-northeast-1                                # 全削除
```

- SSOセッション切れなら `aws sso login --profile <profile>` を自動実行します。ブラウザが使えない環境は `-d` (device code)。
- SSH公開鍵は `-k` → パラメータ `SshPublicKey` → `~/.ssh/id_ed25519.pub` / `id_rsa.pub` の順に使われ、踏み台の `ec2-user` の `authorized_keys` に入ります(コメントは除去)。

## ネットワークモード (`NetworkMode`)

| | `Internet` | `Private` |
|---|---|---|
| 新規VPC(`VpcId`空) | VPC + IGW + パブリックサブネット | VPC + プライベートサブネット(IGW/NATなし、デフォルトルートなし) |
| 既存VPC | `VpcId`/`SubnetId`を指定。IGW or NATで外に出られるサブネット | `VpcId`/`SubnetId`を指定。プライベートサブネット |
| パブリックIP | 新規VPCは付与。既存は`AssociatePublicIp`で選択 | 付与しない |
| VPCエンドポイント | 作らない | 作る(下記) |
| 追加ツール (kubectl, eksctl, helm) | 起動時に自動導入 | `HttpProxy`指定時のみ自動導入 (下記) |

### Privateモードで作成されるVPCエンドポイント

- 常に作成: `s3`(Gateway) / `ssm` / `ssmmessages` / `ec2messages` / `sts`
  (SSM接続とassume roleに必須。`CreateVpcEndpoints=false` で全て作成しない)
- `EnableBuilderEndpoints=true`(既定)で追加: `ec2` `eks` `ecr.api` `ecr.dkr` `logs` `elasticloadbalancing` `autoscaling` `kms` `secretsmanager` `cloudformation` `sqs` `events`
- Interface型はPrivate DNS有効、443をVPC CIDRから許可。踏み台と同じサブネット(1AZ)に配置されます。
  EKSノードを複数AZに置く段階で、必要なAZにもエンドポイントを追加してください。
- 既存VPC指定時は、VPC CIDRと(S3 Gateway用の)ルートテーブルを `deploy.sh` が自動取得します
  (`ExistingVpcCidr` / `RouteTableIds` で上書き可)。
- **既存VPCに同じサービスのエンドポイントが既にある場合**はPrivate DNSが重複して失敗します。
  その場合は `CreateVpcEndpoints=false` にしてください(`deploy.sh` が事前に警告します)。

### Privateモードでのツール導入

踏み台はAmazon Linux 2023なので、AWS CLI v2とSSM Agentは最初からAMIに入っています。

- **jq / git / unzip など(dnf)**: Amazon Linuxのリポジトリ(S3上)から、S3 Gatewayエンドポイント経由で導入する想定です。
  ※この経路は公式ドキュメントで確認できておらず、実機でも未検証です。失敗しても起動処理は続行します(`/var/log/bastion-bootstrap.log`)。
- **kubectl / eksctl / helm**: pkgs.k8s.io・GitHubなどインターネットが必要です。Privateモードでは `HttpProxy`
  (VPCから到達できるプロキシ)が指定された場合のみ導入し、なければスキップします。
  その場合は下記のSSH経由で手元からコピーしてください。

```bash
scp kubectl eksctl helm eks-bastion:/tmp/
ssh eks-bastion 'sudo install -m 0755 /tmp/{kubectl,eksctl,helm} /usr/local/bin/'
```

`HttpProxy` 指定時、Privateモードでは `no_proxy` に `.amazonaws.com` が追加され、AWS APIとAmazon Linuxのリポジトリはプロキシを通らずエンドポイントへ直接向かいます。

## SSMポートフォワード経由のSSH

踏み台のSGにインバウンドはありません。SSHはSSMのトンネル経由のみです。
`deploy.sh` の最後に、値の入った設定例が表示されます。

```sshconfig
# ~/.ssh/config
Host eks-bastion
  HostName i-0123456789abcdef0
  User ec2-user
  IdentityFile ~/.ssh/id_ed25519
  ProxyCommand aws ssm start-session --target %h --document-name AWS-StartSSHSession --parameters portNumber=%p --region ap-northeast-1 --profile <sso-profile>
```

```bash
ssh eks-bastion                                    # ログイン
scp file eks-bastion:/tmp/                         # ファイル転送
ssh -L 8443:<private-host-name>:443 eks-bastion    # メンテ用Web UIへ → https://localhost:8443

# ProxyCommandを使わず、明示的にポートフォワードする場合
aws ssm start-session --target <instance-id> --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["22"],"localPortNumber":["2222"]}'
ssh -p 2222 ec2-user@localhost
```

プロキシ配下ではSession Manager pluginも `HTTPS_PROXY` を参照します。

## 踏み台上での権限

```bash
eks-builder-shell                       # EksBuilderRoleをassumeした状態のシェル
aws --profile eks-builder sts get-caller-identity
```

## 注意点

- `EksBuilderRole` は `iam:*` を含む広範な権限です。踏み台に入れる人=ほぼ管理者と考えてください。
  さらに絞るなら Permissions Boundary や、踏み台ロール自身を変更させないDenyの追加を推奨します。
- `ImageId` は既定でAmazon Linux 2023の最新AMI(x86_64)に解決されます(`/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64`)。
  CFnがパラメータを解決するだけなので、Privateでも問題ありません。更新時に新AMIが出ているとインスタンスが置換されます。固定したい場合は `ami-xxxx` を指定してください。
- Amazon Linux 2023のAMIにはSSM Agentが含まれます。Privateモードでもエンドポイント経由で登録されます。
- `NetworkMode` を既存スタックで切り替えると、サブネット/ルート/IGW/エンドポイントが入れ替わり、インスタンスも置換される場合があります。
- `cleanup.sh` はこのスタックで作ったものだけを削除します。EKSクラスタ構築時に作ったリソース(ENI・SG・NAT GW・追加のVPCエンドポイント・LB等)を先に削除しないと、新規作成したVPCの削除に失敗します(失敗時は残存物を表示します)。
- CodeCommit は新規顧客の受付を終了しているため、権限は含めていますが利用可否は環境依存です。
