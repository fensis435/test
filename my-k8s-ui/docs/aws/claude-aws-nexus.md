
## 全体構成

```
[開発者PC]
    ↓ AWS SSM Session Manager（インターネット経由だがSSH不要）
[踏み台EC2 or 直接対象EC2]
    ↓ VPC内部通信
[Nexus EC2（Private Subnet）]
    ↓
[各サーバー] → Nexusからパッケージ取得
```

---

## 前提条件

- VPC・Private Subnetは作成済み
- インターネットゲートウェイ**なし**
- NAT Gateway**なし**

---

## Step 1: 必要なVPCエンドポイントを作成

SSM経由アクセスに必要なエンドポイントです（これがないとSSMが使えない）。

| エンドポイント | 用途 |
|---|---|
| `com.amazonaws.ap-northeast-1.ssm` | SSM本体 |
| `com.amazonaws.ap-northeast-1.ssmmessages` | SSMセッション |
| `com.amazonaws.ap-northeast-1.ec2messages` | EC2とSSM通信 |
| `com.amazonaws.ap-northeast-1.s3` | パッケージ取得用（Gateway型） |

```bash
# SSM用エンドポイント（Interface型）× 3個
aws ec2 create-vpc-endpoint \
  --vpc-id vpc-xxxxxxxx \
  --vpc-endpoint-type Interface \
  --service-name com.amazonaws.ap-northeast-1.ssm \
  --subnet-ids subnet-xxxxxxxx \
  --security-group-ids sg-xxxxxxxx

# S3用（Gateway型）← 無料なので必ず作る
aws ec2 create-vpc-endpoint \
  --vpc-id vpc-xxxxxxxx \
  --vpc-endpoint-type Gateway \
  --service-name com.amazonaws.ap-northeast-1.s3 \
  --route-table-ids rtb-xxxxxxxx
```

---

## Step 2: IAMロール作成（EC2にアタッチ用）

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ssm:UpdateInstanceInformation",
        "ssmmessages:CreateControlChannel",
        "ssmmessages:CreateDataChannel",
        "ssmmessages:OpenControlChannel",
        "ssmmessages:OpenDataChannel",
        "ec2messages:AcknowledgeMessage",
        "ec2messages:DeleteMessage",
        "ec2messages:FailMessage",
        "ec2messages:GetEndpoint",
        "ec2messages:GetMessages",
        "ec2messages:SendReply",
        "s3:GetObject"
      ],
      "Resource": "*"
    }
  ]
}
```

```bash
# ロール作成
aws iam create-role \
  --role-name NexusEC2Role \
  --assume-role-policy-document file://trust-policy.json

# ポリシーアタッチ
aws iam attach-role-policy \
  --role-name NexusEC2Role \
  --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
```

---

## Step 3: Nexus用EC2を起動

**スペック推奨**
| 項目 | 推奨 |
|---|---|
| インスタンスタイプ | t3.medium以上（メモリ4GB必須） |
| OS | Amazon Linux 2023 |
| ストレージ | 100GB以上（gp3） |
| Subnet | Private Subnet |
| パブリックIP | **なし** |

```bash
aws ec2 run-instances \
  --image-id ami-xxxxxxxxxx \
  --instance-type t3.medium \
  --subnet-id subnet-xxxxxxxx \
  --security-group-ids sg-xxxxxxxx \
  --iam-instance-profile Name=NexusEC2Role \
  --block-device-mappings '[{"DeviceName":"/dev/xvda","Ebs":{"VolumeSize":100,"VolumeType":"gp3"}}]' \
  --no-associate-public-ip-address \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=nexus-server}]'
```

---

## Step 4: SSMでEC2に接続

```bash
# ローカルPCから
aws ssm start-session \
  --target i-xxxxxxxxxxxxxxxxx \
  --region ap-northeast-1
```

---

## Step 5: Nexusをインストール

ここが**完全Private環境の最大の難関**です。  
インターネットに繋がらないのでNexusのインストーラーを事前にS3に置いておきます。

### 事前準備（インターネット接続できる環境で）
```bash
# Nexusをダウンロード
wget https://download.sonatype.com/nexus/3/nexus-3.x.x-unix.tar.gz

# S3にアップロード
aws s3 cp nexus-3.x.x-unix.tar.gz s3://my-company-packages/nexus/
```

### EC2上での作業（SSMセッション内）
```bash
# S3からダウンロード（VPCエンドポイント経由）
aws s3 cp s3://my-company-packages/nexus/nexus-3.x.x-unix.tar.gz /opt/

# Java導入（Amazon Linux 2023はデフォルトでJava利用可能）
sudo dnf install java-17-amazon-corretto -y

# 展開
cd /opt
sudo tar -xzf nexus-3.x.x-unix.tar.gz
sudo mv nexus-3.x.x nexus
sudo mv sonatype-work /opt/sonatype-work

# nexusユーザー作成
sudo useradd -r -m -d /opt/nexus nexus
sudo chown -R nexus:nexus /opt/nexus /opt/sonatype-work

# 実行ユーザー設定
echo 'run_as_user="nexus"' | sudo tee /opt/nexus/bin/nexus.rc
```

---

## Step 6: systemdサービス登録

```bash
sudo tee /etc/systemd/system/nexus.service << 'EOF'
[Unit]
Description=Nexus Repository Manager
After=network.target

[Service]
Type=forking
LimitNOFILE=65536
ExecStart=/opt/nexus/bin/nexus start
ExecStop=/opt/nexus/bin/nexus stop
User=nexus
Restart=on-abort
TimeoutSec=600

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable nexus
sudo systemctl start nexus
```

---

## Step 7: 動作確認 & 初期パスワード取得

```bash
# 起動確認
sudo systemctl status nexus

# ログ確認
tail -f /opt/sonatype-work/nexus3/log/nexus.log

# 初期パスワード確認
cat /opt/sonatype-work/nexus3/admin.password
```

---

## Step 8: ブラウザでアクセス（SSMポートフォワード）

Nexus UIにはブラウザでアクセスするため、SSMのポートフォワードを使います。

```bash
# ローカルPCで実行
aws ssm start-session \
  --target i-xxxxxxxxxxxxxxxxx \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["8081"],"localPortNumber":["8081"]}'

# ブラウザで http://localhost:8081 にアクセス
```

初期ログイン：`admin` / `（Step7で取得したパスワード）`

---

## Step 9: リポジトリ設定

ブラウザのUI上で以下を作成します。

```
Repository → Create repository
  ├── pypi (hosted)    ← pip用
  ├── npm (hosted)     ← npm用
  ├── yum (hosted)     ← yum用
  ├── apt (hosted)     ← apt用
  └── docker (hosted)  ← Docker用
```

---

## 全体の流れまとめ

```
1. VPCエンドポイント作成（SSM用・S3用）
2. IAMロール作成
3. EC2起動（Private Subnet・パブリックIPなし）
4. NexusインストーラーをあらかじめS3に配置
5. SSMで接続 → S3からNexusを取得 → インストール
6. SSMポートフォワードでUI設定
7. リポジトリ作成
8. 各サーバーからNexusを向き先に設定
```

---
---

## 前提
NexusのUIにアクセスできている状態（Step8完了後）からです。

---

## 1. yum リポジトリ設定

### Nexus UI で作成
```
Repository → Create repository → yum (hosted)
  Name: yum-private
  Repodata Depth: 1
  Deployment policy: Allow redeploy
```

### パッケージのアップロード（インターネット環境で収集）
```bash
# 必要なRPMを全部ダウンロード
yumdownloader --resolve --destdir=./rpms パッケージ名

# 例：よく使うものをまとめて
yumdownloader --resolve --destdir=./rpms \
  git \
  curl \
  wget \
  vim \
  gcc \
  make \
  openssl \
  openssl-devel

# S3に上げる
aws s3 sync ./rpms/ s3://my-company-packages/rpms/
```

### Private EC2上でNexusにアップロード
```bash
# S3から取得
aws s3 sync s3://my-company-packages/rpms/ ./rpms/

# Nexusにアップロード
for rpm in ./rpms/*.rpm; do
  curl -u admin:password \
    --upload-file "$rpm" \
    "http://nexus-server:8081/repository/yum-private/$(basename $rpm)"
done
```

### 各サーバーのyum設定
```bash
# /etc/yum.repos.d/nexus.repo を作成
sudo tee /etc/yum.repos.d/nexus.repo << 'EOF'
[nexus]
name=Nexus Repository
baseurl=http://nexus-server:8081/repository/yum-private/
enabled=1
gpgcheck=0
EOF

# 動作確認
sudo yum install git -y
```

---

## 2. pip リポジトリ設定

### Nexus UI で作成
```
Repository → Create repository → pypi (hosted)
  Name: pypi-private
  Deployment policy: Allow redeploy
```

### パッケージ収集（インターネット環境で）
```bash
# requirements.txtから全部ダウンロード
pip download -r requirements.txt \
  --dest ./packages/pypi/ \
  --platform linux_x86_64 \
  --python-version 311 \
  --only-binary=:all:

# requirements.txtがない場合は個別に
pip download \
  django \
  flask \
  requests \
  boto3 \
  numpy \
  pandas \
  -d ./packages/pypi/

# S3に上げる
aws s3 sync ./packages/pypi/ s3://my-company-packages/pypi/
```

### Nexusにアップロード
```bash
# twineをインストール（インターネット環境で）
pip install twine

# S3から取得
aws s3 sync s3://my-company-packages/pypi/ ./packages/pypi/

# まとめてアップロード
twine upload \
  --repository-url http://nexus-server:8081/repository/pypi-private/ \
  --username admin \
  --password password \
  ./packages/pypi/*
```

### 各サーバーのpip設定
```bash
# pip.confを作成
mkdir -p ~/.config/pip
tee ~/.config/pip/pip.conf << 'EOF'
[global]
index-url = http://admin:password@nexus-server:8081/repository/pypi-private/simple/
trusted-host = nexus-server
EOF

# 動作確認
pip install requests
```

---

## 3. gem リポジトリ設定

### Nexus UI で作成
```
Repository → Create repository → rubygems (hosted)
  Name: gem-private
  Deployment policy: Allow redeploy
```

### パッケージ収集（インターネット環境で）
```bash
# Gemfileから全部ダウンロード
bundle package --all
# → vendor/cache/ 以下に.gemファイルが生成される

# Gemfileがない場合は個別に
gem fetch rails -v 7.0.0
gem fetch nokogiri
gem fetch puma

# 依存関係も含めて全部取得
gem install --no-document \
  rails \
  nokogiri \
  puma \
  --install-dir ./gems-dir

find ./gems-dir -name "*.gem" -exec cp {} ./packages/gems/ \;

# S3に上げる
aws s3 sync ./packages/gems/ s3://my-company-packages/gems/
```

### Nexusにアップロード
```bash
# S3から取得
aws s3 sync s3://my-company-packages/gems/ ./packages/gems/

# まとめてアップロード
for gem in ./packages/gems/*.gem; do
  curl -u admin:password \
    --upload-file "$gem" \
    "http://nexus-server:8081/repository/gem-private/"
done
```

### 各サーバーのgem設定
```bash
# デフォルトのソースを変更
gem sources --remove https://rubygems.org/
gem sources --add http://nexus-server:8081/repository/gem-private/

# bundlerの場合
bundle config mirror.https://rubygems.org \
  http://nexus-server:8081/repository/gem-private/

# 動作確認
gem install rails
```

---

## 4. npm リポジトリ設定

### Nexus UI で作成
```
Repository → Create repository → npm (hosted)
  Name: npm-private
  Deployment policy: Allow redeploy
```

### パッケージ収集（インターネット環境で）
```bash
# package.jsonから全部ダウンロード
npm install
# node_modules以下に展開されるので.tgzに変換

# 個別にpack
npm pack react
npm pack react-dom
npm pack lodash
npm pack express
npm pack typescript
# → .tgzファイルが生成される

# まとめて取得するスクリプト
cat package.json | jq -r '.dependencies | keys[]' | while read pkg; do
  npm pack "$pkg"
done

# S3に上げる
aws s3 sync ./*.tgz s3://my-company-packages/npm/
```

### Nexusにアップロード
```bash
# Nexusへの認証設定
npm config set registry http://nexus-server:8081/repository/npm-private/

# 認証トークン取得
curl -u admin:password \
  http://nexus-server:8081/service/rest/v1/security/users \
  -H "Content-Type: application/json"

# S3から取得
aws s3 sync s3://my-company-packages/npm/ ./packages/npm/

# まとめてアップロード
for tgz in ./packages/npm/*.tgz; do
  npm publish "$tgz" \
    --registry http://nexus-server:8081/repository/npm-private/
done
```

### 各サーバーのnpm設定
```bash
# .npmrcを作成
tee ~/.npmrc << 'EOF'
registry=http://nexus-server:8081/repository/npm-private/
always-auth=true
//nexus-server:8081/repository/npm-private/:username=admin
//nexus-server:8081/repository/npm-private/:password=<base64エンコードしたパスワード>
EOF

# 動作確認
npm install express
```

---

## 全体の流れまとめ

```
【インターネット接続できる環境】
  ↓ yumdownloader / pip download / gem fetch / npm pack
  ↓ S3にアップロード
  
【Private環境 Nexusサーバー上】
  ↓ S3からダウンロード（VPCエンドポイント経由）
  ↓ Nexusにアップロード（curl / twine / npm publish）

【Private環境 各サーバー】
  yum.repos.d / pip.conf / gem sources / .npmrc
  ↓ Nexusを向き先に設定
  ↓ 通常通りインストールできる！
```

---

## 注意点

**依存関係の漏れが一番多いトラブルです。**

```bash
# pip: 依存関係含めて確認
pip download パッケージ名 -d ./test/ --dry-run

# gem: 依存関係確認
gem dependency パッケージ名 --pipe

# npm: 依存関係ツリー確認
npm ls --all
```

インストール失敗したら大抵「依存パッケージが足りない」なので、エラーメッセージのパッケージ名を追加収集して再アップロードというサイクルになります。

---

## apt リポジトリ設定

### Nexus UI で作成
```
Repository → Create repository → apt (hosted)
  Name: apt-private
  Distribution: jammy  ← Ubuntuのバージョンに合わせる
  Signing Key: （GPGキーを生成して設定）
  Deployment policy: Allow redeploy
```

---

## GPGキーの生成（署名に必要）

aptはパッケージの署名検証があるため、yumより少し手間がかかります。

```bash
# GPGキー生成（インターネット環境でも Private環境でも可）
gpg --batch --gen-key << 'EOF'
Key-Type: RSA
Key-Length: 4096
Subkey-Type: RSA
Subkey-Length: 4096
Name-Real: My Company
Name-Email: nexus@mycompany.com
Expire-Date: 0
%no-passphrase
%commit
EOF

# 公開鍵をエクスポート
gpg --export --armor nexus@mycompany.com > my-company.asc

# 秘密鍵をエクスポート（Nexusに登録する）
gpg --export-secret-keys --armor nexus@mycompany.com > my-company-private.asc
```

### NexusにGPGキーを登録
```
Security → Signing Keys → Create signing key
  秘密鍵（my-company-private.asc の内容）を貼り付け
```

---

## パッケージ収集（インターネット環境で）

```bash
# 必要なDEBパッケージをダウンロード
sudo apt-get install --download-only -o Dir::Cache=./apt-cache パッケージ名

# もしくはapt-downloadを使う
mkdir -p ./packages/apt
cd ./packages/apt

# 個別ダウンロード
apt-get download \
  git \
  curl \
  wget \
  vim \
  gcc \
  make \
  openssl \
  libssl-dev \
  python3 \
  python3-pip

# 依存関係も含めて全部取得
apt-get install --print-uris -qq git curl vim | \
  grep -oP "(?<=').*(?=')" | \
  wget -i - -P ./packages/apt/

# S3にアップロード
aws s3 sync ./packages/apt/ s3://my-company-packages/apt/
```

---

## Nexusにアップロード

```bash
# S3から取得
aws s3 sync s3://my-company-packages/apt/ ./packages/apt/

# まとめてアップロード
for deb in ./packages/apt/*.deb; do
  curl -u admin:password \
    --upload-file "$deb" \
    "http://nexus-server:8081/repository/apt-private/"
done
```

---

## 各サーバーのapt設定

```bash
# 公開鍵を登録
curl http://nexus-server:8081/repository/apt-private/dists/jammy/Release.gpg \
  | sudo apt-key add -

# もしくは最近のUbuntu推奨の方法
curl http://nexus-server:8081/repository/apt-private/my-company.asc \
  | sudo gpg --dearmor \
  | sudo tee /etc/apt/trusted.gpg.d/my-company.gpg > /dev/null

# ソースリストを設定
sudo tee /etc/apt/sources.list.d/nexus.list << 'EOF'
deb http://nexus-server:8081/repository/apt-private jammy main
EOF

# デフォルトのUbuntuリポジトリを無効化（完全Private環境の場合）
sudo mv /etc/apt/sources.list /etc/apt/sources.list.bak

# パッケージリスト更新
sudo apt-get update

# 動作確認
sudo apt-get install git -y
```

---

## yumとaptの比較

| | yum（RPM） | apt（DEB） |
|---|---|---|
| **対象OS** | Amazon Linux / RHEL / CentOS | Ubuntu / Debian |
| **署名** | 任意（gpgcheck=0でスキップ可） | **ほぼ必須（手間がかかる）** |
| **依存解決** | 自動 | 自動 |
| **Nexus設定難易度** | 低 | 中（GPG周りが面倒） |

---

## aptで一番ハマるポイント

**GPG署名エラーが一番多いトラブルです。**

```bash
# エラー例
W: GPG error: http://nexus-server:8081 jammy InRelease:
   The following signatures couldn't be verified...

# 対処法①：公開鍵が正しく登録されているか確認
apt-key list

# 対処法②：とりあえず署名チェックを無効化（テスト時のみ）
sudo tee /etc/apt/sources.list.d/nexus.list << 'EOF'
deb [trusted=yes] http://nexus-server:8081/repository/apt-private jammy main
EOF
```

`[trusted=yes]` はセキュリティ的に本番では推奨しませんが、動作確認時に原因の切り分けとして使えます。

---

## 5種類全部まとめ

```
Nexus
  ├── yum-private   → Amazon Linux / RHEL系
  ├── apt-private   → Ubuntu / Debian系
  ├── pypi-private  → Python
  ├── gem-private   → Ruby
  └── npm-private   → JavaScript
```

これで主要なパッケージは全部Nexus一箇所で管理できます。

---
