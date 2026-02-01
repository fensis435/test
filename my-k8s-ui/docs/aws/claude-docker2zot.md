# Kubernetes + containerd 環境を Docker から nerdctl + Zot に完全移行する手順

## 現在の環境（想定）

```
【現在】
- K8s + containerd で動作
- イメージビルド: docker + docker-compose
- Private Registry: Docker Registry (docker で起動)
- 問題: Kubespray が docker をアンインストールする
```

## 移行後の環境

```
【移行後】
- K8s + containerd (変更なし)
- イメージビルド: nerdctl + nerdctl compose
- Private Registry: Zot (systemd サービス)
- メリット: Docker 完全不要、自動GC、クリーンアップ簡単
```


```
nerdctl と Zot の関係
┌─────────────────────────────────────────────┐
│ 開発者の操作                                                                             │
└─────────────────────────────────────────────┘
                              │
                              │ nerdctl build -t localhost:5000/myapp:v1 .
                              ▼
┌─────────────────────────────────────────────┐
│ nerdctl (CLI)                                                                            │
│ - ビルド指示                                                                             │
│ - プッシュ指示                                                                           │
└──────────────┬──────────────────────────────┘
                              │
                              │ gRPC通信
                              ▼
┌─────────────────────────────────────────────┐
│ containerd                                                                               │
│ - イメージをビルド                                                                       │
│ - ローカルにイメージ保存                                                                 │
└──────────────┬──────────────────────────────┘
                              │
                              │ nerdctl push localhost:5000/myapp:v1
                              │
                              │ HTTP/HTTPS
                              ▼
┌─────────────────────────────────────────────┐
│ Zot Registry (localhost:5000)                                                            │
│ - イメージを受け取る                                                                     │
│ - /var/lib/zot に保存                                                                    │
│ - 自動GCで古いイメージ削除                                                               │
└─────────────────────────────────────────────┘
```

---

## 移行手順

### **Phase 1: Zot Registry のセットアップ（既存Registryの代替）**

#### 1-1. Zot のインストール

```bash
# Zot バイナリダウンロード
wget https://github.com/project-zot/zot/releases/download/v2.0.1/zot-linux-amd64
chmod +x zot-linux-amd64
sudo mv zot-linux-amd64 /usr/local/bin/zot

# 確認
zot --help
```

#### 1-2. Zot の設定ファイル作成

```bash
# ディレクトリ作成
sudo mkdir -p /etc/zot /var/lib/zot

# 設定ファイル作成
sudo tee /etc/zot/config.json <<EOF
{
  "distSpecVersion": "1.1.0",
  "storage": {
    "rootDirectory": "/var/lib/zot",
    "gc": true,
    "dedupe": true,
    "gcDelay": "1h",
    "gcInterval": "6h"
  },
  "http": {
    "address": "0.0.0.0",
    "port": "5000"
  },
  "log": {
    "level": "info",
    "output": "/var/log/zot.log"
  }
}
EOF
```

#### 1-3. Zot を systemd サービスとして登録

```bash
sudo tee /etc/systemd/system/zot.service <<EOF
[Unit]
Description=Zot OCI Registry
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/zot serve /etc/zot/config.json
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# サービス有効化・起動
sudo systemctl daemon-reload
sudo systemctl enable zot
sudo systemctl start zot

# 確認
sudo systemctl status zot
curl http://localhost:5000/v2/_catalog
```

#### 1-4. 既存の Docker Registry からイメージを移行

```bash
# 既存 Docker Registry のイメージ一覧取得
OLD_REGISTRY="localhost:5000"  # 既存のレジストリアドレス
NEW_REGISTRY="localhost:5000"  # Zot (同じポートの場合は後で切り替え)

# もし既存が別ポートなら
# OLD_REGISTRY="localhost:5001"
# NEW_REGISTRY="localhost:5000"

# イメージ一覧取得
curl http://${OLD_REGISTRY}/v2/_catalog

# 各イメージを pull → tag → push
# 例: myapp というイメージを移行
docker pull ${OLD_REGISTRY}/myapp:v1
docker tag ${OLD_REGISTRY}/myapp:v1 ${NEW_REGISTRY}/myapp:v1

# この時点で nerdctl に切り替え
nerdctl tag ${OLD_REGISTRY}/myapp:v1 ${NEW_REGISTRY}/myapp:v1
nerdctl push ${NEW_REGISTRY}/myapp:v1 --insecure-registry
```

**自動移行スクリプト例:**

```bash
#!/bin/bash
# migrate-images.sh

OLD_REGISTRY="localhost:5001"  # 古い Docker Registry
NEW_REGISTRY="localhost:5000"  # 新しい Zot

# 全イメージ取得
REPOS=$(curl -s http://${OLD_REGISTRY}/v2/_catalog | jq -r '.repositories[]')

for REPO in $REPOS; do
  echo "Migrating repository: $REPO"
  
  # タグ一覧取得
  TAGS=$(curl -s http://${OLD_REGISTRY}/v2/${REPO}/tags/list | jq -r '.tags[]')
  
  for TAG in $TAGS; do
    echo "  - Tag: $TAG"
    
    # Pull (docker で)
    docker pull ${OLD_REGISTRY}/${REPO}:${TAG}
    
    # Tag
    docker tag ${OLD_REGISTRY}/${REPO}:${TAG} ${NEW_REGISTRY}/${REPO}:${TAG}
    
    # Push (nerdctl で)
    nerdctl push ${NEW_REGISTRY}/${REPO}:${TAG} --insecure-registry
  done
done

echo "Migration completed"
```

#### 1-5. 既存 Docker Registry を停止

```bash
# Docker で起動している Registry を停止
docker stop registry
docker rm registry

# または systemd で管理している場合
# sudo systemctl stop docker-registry
# sudo systemctl disable docker-registry
```

---

### **Phase 2: nerdctl のセットアップ（docker-compose の代替）**

#### 2-1. nerdctl のインストール

```bash
# nerdctl full パッケージをダウンロード（CNI、buildkit含む）
wget https://github.com/containerd/nerdctl/releases/download/v1.7.3/nerdctl-full-1.7.3-linux-amd64.tar.gz

# システムに展開
sudo tar Cxzvf /usr/local nerdctl-full-1.7.3-linux-amd64.tar.gz

# 確認
nerdctl version
nerdctl compose version
```

#### 2-2. containerd の設定（insecure registry 許可）

```bash
# 既存設定のバックアップ
sudo cp /etc/containerd/config.toml /etc/containerd/config.toml.backup

# 設定追加
sudo tee -a /etc/containerd/config.toml <<EOF

[plugins."io.containerd.grpc.v1.cri".registry]
  [plugins."io.containerd.grpc.v1.cri".registry.mirrors]
    [plugins."io.containerd.grpc.v1.cri".registry.mirrors."localhost:5000"]
      endpoint = ["http://localhost:5000"]
  
  [plugins."io.containerd.grpc.v1.cri".registry.configs]
    [plugins."io.containerd.grpc.v1.cri".registry.configs."localhost:5000".tls]
      insecure_skip_verify = true
EOF

# containerd 再起動
sudo systemctl restart containerd
```

#### 2-3. buildkit の起動（nerdctl ビルド用）

```bash
# buildkit を systemd で起動
sudo systemctl enable --now buildkit

# 確認
sudo systemctl status buildkit
```

---

### **Phase 3: docker-compose.yml を nerdctl compose に移行**

#### 3-1. 既存 docker-compose.yml の確認

```yaml
# 例: docker-compose.yml
version: '3.8'
services:
  app:
    build: .
    image: localhost:5000/myapp:latest
    ports:
      - "8080:8080"
```

#### 3-2. nerdctl compose での動作確認

```bash
# 既存の docker-compose.yml をそのまま使用可能
cd /path/to/your/project

# ビルド
nerdctl compose build

# イメージ確認
nerdctl images

# プッシュ（必要に応じて）
nerdctl compose push
```

#### 3-3. ビルド & プッシュのスクリプト化

```bash
# build-and-push.sh
#!/bin/bash

set -e

PROJECT_DIR="/path/to/your/project"
REGISTRY="localhost:5000"
IMAGE_NAME="myapp"
TAG="${1:-latest}"

cd "$PROJECT_DIR"

echo "=== Building image ==="
nerdctl compose build

echo "=== Tagging image ==="
nerdctl tag ${IMAGE_NAME}:${TAG} ${REGISTRY}/${IMAGE_NAME}:${TAG}

echo "=== Pushing to registry ==="
nerdctl push ${REGISTRY}/${IMAGE_NAME}:${TAG} --insecure-registry

echo "=== Build and push completed ==="
nerdctl images | grep ${IMAGE_NAME}
```

```bash
chmod +x build-and-push.sh

# 実行
./build-and-push.sh v1.0.0
```

---

### **Phase 4: Kubernetes からの利用設定**

#### 4-1. 各 K8s ノードで containerd 設定を同期

```bash
# 全ノードで実行（Phase 2-2 の設定）
# または kubespray/ansible で一括設定

# 例: ansible playbook
# hosts: all
# tasks:
#   - name: Configure containerd for local registry
#     blockinfile:
#       path: /etc/containerd/config.toml
#       block: |
#         [plugins."io.containerd.grpc.v1.cri".registry.mirrors."localhost:5000"]
#           endpoint = ["http://localhost:5000"]
#         [plugins."io.containerd.grpc.v1.cri".registry.configs."localhost:5000".tls]
#           insecure_skip_verify = true
#   - name: Restart containerd
#     systemd:
#       name: containerd
#       state: restarted
```

#### 4-2. Kubernetes manifest の更新

```yaml
# deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
  namespace: default
spec:
  replicas: 3
  selector:
    matchLabels:
      app: myapp
  template:
    metadata:
      labels:
        app: myapp
    spec:
      containers:
      - name: myapp
        image: localhost:5000/myapp:v1.0.0
        # または <registry-node-ip>:5000/myapp:v1.0.0
        ports:
        - containerPort: 8080
```

```bash
# デプロイ
kubectl apply -f deployment.yaml

# Pod の起動確認
kubectl get pods
kubectl describe pod <pod-name>

# イメージが正しく pull されているか確認
kubectl get pod <pod-name> -o jsonpath='{.status.containerStatuses[0].imageID}'
```

---

### **Phase 5: 自動クリーンアップの設定**

#### 5-1. nerdctl 定期クリーンアップスクリプト

```bash
sudo tee /usr/local/bin/nerdctl-cleanup.sh <<'EOF'
#!/bin/bash

LOG_FILE="/var/log/nerdctl-cleanup.log"

{
  echo "=== Cleanup started: $(date) ==="
  
  echo "--- Before ---"
  nerdctl system df
  
  echo "--- Pruning build cache ---"
  nerdctl builder prune -a -f
  
  echo "--- Pruning unused images ---"
  nerdctl image prune -a -f
  
  echo "--- Pruning stopped containers ---"
  nerdctl container prune -f
  
  echo "--- Pruning unused volumes ---"
  nerdctl volume prune -f
  
  echo "--- After ---"
  nerdctl system df
  
  echo "=== Cleanup completed: $(date) ==="
  echo ""
} >> "$LOG_FILE" 2>&1
EOF

sudo chmod +x /usr/local/bin/nerdctl-cleanup.sh
```

#### 5-2. cron 設定

```bash
# 毎日午前 2 時に実行
echo "0 2 * * * root /usr/local/bin/nerdctl-cleanup.sh" | sudo tee -a /etc/crontab

# 確認
sudo cat /etc/crontab | grep nerdctl
```

#### 5-3. Zot の自動 GC 確認

```bash
# Zot の設定で GC が有効か確認
cat /etc/zot/config.json | jq '.storage.gc'
# true が表示されれば OK

# Zot のログで GC 実行を確認
sudo journalctl -u zot | grep -i "garbage"
```

---

### **Phase 6: Docker の完全削除**

#### 6-1. Docker の停止・削除

```bash
# Docker サービス停止
sudo systemctl stop docker
sudo systemctl disable docker

# Docker 削除（Ubuntu/Debian の場合）
sudo apt-get purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo apt-get autoremove -y

# Docker データ削除（注意: 既存イメージが消えます）
sudo rm -rf /var/lib/docker

# 確認
docker --version
# command not found が表示されれば OK
```

#### 6-2. docker-compose 削除

```bash
# docker-compose 削除
sudo rm /usr/local/bin/docker-compose

# 確認
docker-compose --version
# command not found が表示されれば OK
```

---

## 移行後の運用フロー

### **開発フロー**

```bash
# 1. コード変更

# 2. イメージビルド
cd /path/to/project
nerdctl compose build
# または
nerdctl build -t localhost:5000/myapp:v1.0.1 .

# 3. レジストリにプッシュ
nerdctl push localhost:5000/myapp:v1.0.1 --insecure-registry

# 4. Kubernetes にデプロイ
kubectl set image deployment/myapp myapp=localhost:5000/myapp:v1.0.1
# または
kubectl apply -f deployment.yaml
```

### **定期メンテナンス**

```bash
# ローカルキャッシュクリーンアップ（自動実行済み）
/usr/local/bin/nerdctl-cleanup.sh

# Zot レジストリの状態確認
curl http://localhost:5000/v2/_catalog
du -sh /var/lib/zot

# サービス状態確認
sudo systemctl status zot
sudo systemctl status buildkit
sudo systemctl status containerd
```

---

## トラブルシューティング

### **イメージが push できない**

```bash
# Zot の起動確認
sudo systemctl status zot
curl http://localhost:5000/v2/

# containerd の設定確認
nerdctl info | grep -A 5 "Insecure Registries"

# ログ確認
sudo journalctl -u zot -f
nerdctl --debug push localhost:5000/myapp:v1 --insecure-registry
```

### **Kubernetes で pull できない**

```bash
# ノードの containerd 設定確認
ssh <node-name>
cat /etc/containerd/config.toml | grep -A 5 "localhost:5000"

# レジストリへの疎通確認
curl http://localhost:5000/v2/_catalog

# Pod のイベント確認
kubectl describe pod <pod-name>
```

### **ビルドが遅い/失敗する**

```bash
# buildkit の状態確認
sudo systemctl status buildkit

# ビルドキャッシュ削除
nerdctl builder prune -a -f

# ディスク容量確認
df -h /var/lib/containerd
df -h /var/lib/zot
```

---

## 移行チェックリスト

- [ ] Zot インストール・起動確認
- [ ] 既存イメージを Zot に移行
- [ ] 既存 Docker Registry 停止
- [ ] nerdctl インストール
- [ ] containerd 設定更新（insecure registry）
- [ ] buildkit 起動
- [ ] docker-compose.yml → nerdctl compose で動作確認
- [ ] 全 K8s ノードの containerd 設定同期
- [ ] Kubernetes からのイメージ pull 確認
- [ ] 自動クリーンアップスクリプト設定
- [ ] Docker 完全削除
- [ ] 運用ドキュメント更新

---

## まとめ

この手順で、Docker に一切依存しない **nerdctl + Zot** 環境が構築できます。

**メリット:**
- Kubespray が Docker をアンインストールしても問題なし
- 自動 GC でストレージ管理が楽
- docker-compose.yml がそのまま使える
- クリーンアップが簡単

何か不明点や追加で必要な手順があれば教えてください！

---
---
<br>
<br>
<br>

# === Zotをリモートホストに配置する場合の手順 ===

## リモートホスト構成

```
┌─────────────────────────────┐
│ Registry Server             │
│ registry.example.com        │
│ (または 192.168.1.100)      │
│                             │
│ - Zot Registry (port 5000)  │
│ - TLS証明書 (推奨)          │
└──────────────┬──────────────┘
               │
               │ Network
               │
    ┌──────────┼──────────┬──────────┐
    │          │          │          │
┌───▼────┐ ┌──▼────┐ ┌──▼────┐ ┌──▼────┐
│ Dev PC │ │ K8s   │ │ K8s   │ │ K8s   │
│        │ │ Node1 │ │ Node2 │ │ Node3 │
│nerdctl │ │       │ │       │ │       │
└────────┘ └───────┘ └───────┘ └───────┘
```

---

## セットアップ手順

### **1. Registry Server での Zot セットアップ**

#### 1-1. Zot インストール（Registry Server）

```bash
# Registry Server にログイン
ssh user@registry.example.com

# Zot インストール
wget https://github.com/project-zot/zot/releases/download/v2.0.1/zot-linux-amd64
chmod +x zot-linux-amd64
sudo mv zot-linux-amd64 /usr/local/bin/zot
```

#### 1-2. TLS証明書の準備（推奨）

**Option A: Let's Encrypt（ドメインがある場合）**

```bash
# certbot インストール
sudo apt-get update
sudo apt-get install certbot

# 証明書取得
sudo certbot certonly --standalone -d registry.example.com

# 証明書の場所
# /etc/letsencrypt/live/registry.example.com/fullchain.pem
# /etc/letsencrypt/live/registry.example.com/privkey.pem
```

**Option B: 自己署名証明書（テスト環境）**

```bash
# 証明書ディレクトリ作成
sudo mkdir -p /etc/zot/certs

# 自己署名証明書作成
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/zot/certs/registry.key \
  -out /etc/zot/certs/registry.crt \
  -subj "/CN=registry.example.com"
```

#### 1-3. Zot 設定ファイル（TLS対応）

```bash
sudo mkdir -p /etc/zot /var/lib/zot

# HTTPS 有効化
sudo tee /etc/zot/config.json <<EOF
{
  "distSpecVersion": "1.1.0",
  "storage": {
    "rootDirectory": "/var/lib/zot",
    "gc": true,
    "dedupe": true,
    "gcDelay": "1h",
    "gcInterval": "6h"
  },
  "http": {
    "address": "0.0.0.0",
    "port": "5000",
    "tls": {
      "cert": "/etc/zot/certs/registry.crt",
      "key": "/etc/zot/certs/registry.key"
    }
  },
  "log": {
    "level": "info",
    "output": "/var/log/zot.log"
  }
}
EOF
```

**insecure（TLSなし）の場合:**

```bash
sudo tee /etc/zot/config.json <<EOF
{
  "distSpecVersion": "1.1.0",
  "storage": {
    "rootDirectory": "/var/lib/zot",
    "gc": true,
    "dedupe": true,
    "gcDelay": "1h",
    "gcInterval": "6h"
  },
  "http": {
    "address": "0.0.0.0",
    "port": "5000"
  },
  "log": {
    "level": "info"
  }
}
EOF
```

#### 1-4. Zot サービス起動

```bash
sudo tee /etc/systemd/system/zot.service <<EOF
[Unit]
Description=Zot OCI Registry
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/zot serve /etc/zot/config.json
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable zot
sudo systemctl start zot

# 確認
sudo systemctl status zot
curl -k https://registry.example.com:5000/v2/_catalog
# または
curl http://registry.example.com:5000/v2/_catalog
```

#### 1-5. ファイアウォール設定

```bash
# ポート 5000 を開放（Ubuntu/Debian の場合）
sudo ufw allow 5000/tcp

# または firewalld の場合
sudo firewall-cmd --permanent --add-port=5000/tcp
sudo firewall-cmd --reload
```

---

### **2. クライアント側の設定（開発PC、K8sノード）**

#### 2-1. 自己署名証明書の場合：証明書を配布

```bash
# Registry Server から証明書をコピー
scp user@registry.example.com:/etc/zot/certs/registry.crt .

# クライアントマシン（各K8sノード、開発PC）にインストール
sudo mkdir -p /usr/local/share/ca-certificates/
sudo cp registry.crt /usr/local/share/ca-certificates/registry.example.com.crt
sudo update-ca-certificates

# または containerd 用に直接配置
sudo mkdir -p /etc/containerd/certs.d/registry.example.com:5000
sudo cp registry.crt /etc/containerd/certs.d/registry.example.com:5000/ca.crt
```

#### 2-2. containerd 設定（各K8sノード）

**HTTPS（自己署名証明書）の場合:**

```bash
sudo tee -a /etc/containerd/config.toml <<EOF

[plugins."io.containerd.grpc.v1.cri".registry]
  [plugins."io.containerd.grpc.v1.cri".registry.mirrors]
    [plugins."io.containerd.grpc.v1.cri".registry.mirrors."registry.example.com:5000"]
      endpoint = ["https://registry.example.com:5000"]
  
  [plugins."io.containerd.grpc.v1.cri".registry.configs]
    [plugins."io.containerd.grpc.v1.cri".registry.configs."registry.example.com:5000".tls]
      ca_file = "/etc/containerd/certs.d/registry.example.com:5000/ca.crt"
EOF

sudo systemctl restart containerd
```

**HTTP（insecure）の場合:**

```bash
sudo tee -a /etc/containerd/config.toml <<EOF

[plugins."io.containerd.grpc.v1.cri".registry]
  [plugins."io.containerd.grpc.v1.cri".registry.mirrors]
    [plugins."io.containerd.grpc.v1.cri".registry.mirrors."registry.example.com:5000"]
      endpoint = ["http://registry.example.com:5000"]
  
  [plugins."io.containerd.grpc.v1.cri".registry.configs]
    [plugins."io.containerd.grpc.v1.cri".registry.configs."registry.example.com:5000".tls]
      insecure_skip_verify = true
EOF

sudo systemctl restart containerd
```

#### 2-3. nerdctl での使用（開発PC）

```bash
# HTTPS の場合
nerdctl build -t registry.example.com:5000/myapp:v1 .
nerdctl push registry.example.com:5000/myapp:v1

# HTTP（insecure）の場合
nerdctl build -t registry.example.com:5000/myapp:v1 .
nerdctl push registry.example.com:5000/myapp:v1 --insecure-registry

# pull
nerdctl pull registry.example.com:5000/myapp:v1 --insecure-registry
```

#### 2-4. Kubernetes manifest 更新

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
spec:
  replicas: 3
  selector:
    matchLabels:
      app: myapp
  template:
    metadata:
      labels:
        app: myapp
    spec:
      containers:
      - name: myapp
        image: registry.example.com:5000/myapp:v1
        ports:
        - containerPort: 8080
```

---

### **3. 認証付きRegistry（推奨）**

#### 3-1. Zot で Basic 認証を有効化

```bash
# htpasswd ツールインストール
sudo apt-get install apache2-utils

# ユーザー作成
sudo mkdir -p /etc/zot/auth
sudo htpasswd -Bc /etc/zot/auth/htpasswd myuser
# パスワード入力: mypassword

# Zot 設定更新
sudo tee /etc/zot/config.json <<EOF
{
  "distSpecVersion": "1.1.0",
  "storage": {
    "rootDirectory": "/var/lib/zot",
    "gc": true,
    "dedupe": true,
    "gcInterval": "6h"
  },
  "http": {
    "address": "0.0.0.0",
    "port": "5000",
    "auth": {
      "htpasswd": {
        "path": "/etc/zot/auth/htpasswd"
      }
    },
    "tls": {
      "cert": "/etc/zot/certs/registry.crt",
      "key": "/etc/zot/certs/registry.key"
    }
  },
  "log": {
    "level": "info"
  }
}
EOF

sudo systemctl restart zot
```

#### 3-2. クライアント側での認証設定

**nerdctl でログイン:**

```bash
nerdctl login registry.example.com:5000
# Username: myuser
# Password: mypassword

# 認証情報は ~/.docker/config.json に保存される
```

**containerd 設定に認証情報を追加:**

```bash
sudo tee -a /etc/containerd/config.toml <<EOF

  [plugins."io.containerd.grpc.v1.cri".registry.configs."registry.example.com:5000".auth]
    username = "myuser"
    password = "mypassword"
EOF

sudo systemctl restart containerd
```

**Kubernetes Secret 作成:**

```bash
kubectl create secret docker-registry regcred \
  --docker-server=registry.example.com:5000 \
  --docker-username=myuser \
  --docker-password=mypassword \
  --docker-email=user@example.com

# Deployment で使用
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
spec:
  template:
    spec:
      imagePullSecrets:
      - name: regcred
      containers:
      - name: myapp
        image: registry.example.com:5000/myapp:v1
```

---

## 構成パターン

### **パターン1: 単一 Registry Server**

```
Registry Server (registry.example.com)
    ↑
    │ push/pull
    │
┌───┼─────┬─────┬─────┐
│   │     │     │     │
Dev  N1   N2   N3   N4
PC   (K8s Nodes)
```

### **パターン2: 複数リージョン（Registry Mirror）**

```
Main Registry (registry-main.example.com)
    │
    │ sync/replicate
    │
┌───┴────┬────────┐
│        │        │
Mirror1  Mirror2  Mirror3
(Tokyo)  (Osaka)  (Fukuoka)
```

---

# Zot コマンド一覧

## Zot CLI コマンド

```bash
# サーバー起動
zot serve <config-file>

# 設定ファイル検証
zot verify <config-file>

# バージョン確認
zot --version

# ヘルプ
zot --help
zot serve --help
```

## Zot 管理用 REST API

```bash
# カタログ取得（全リポジトリ一覧）
curl http://registry.example.com:5000/v2/_catalog

# タグ一覧取得
curl http://registry.example.com:5000/v2/<repo-name>/tags/list

# manifest 取得
curl http://registry.example.com:5000/v2/<repo-name>/manifests/<tag>

# manifest 削除（要認証）
curl -X DELETE http://registry.example.com:5000/v2/<repo-name>/manifests/<digest>

# ヘルスチェック
curl http://registry.example.com:5000/v2/

# 統計情報（Zot 拡張）
curl http://registry.example.com:5000/v2/_zot/ext/search?query={ImageList}
```

---

# nerdctl コマンド一覧

## イメージ管理

```bash
# イメージビルド
nerdctl build -t <image-name>:<tag> .
nerdctl build -t <image-name>:<tag> -f Dockerfile.custom .
nerdctl build --no-cache -t <image-name>:<tag> .

# イメージ一覧
nerdctl images
nerdctl images -a                    # 中間イメージも表示
nerdctl images --format "{{.Repository}}:{{.Tag}}"

# イメージ削除
nerdctl rmi <image-id>
nerdctl rmi <image-name>:<tag>
nerdctl image prune                  # 未使用イメージ削除
nerdctl image prune -a               # 全未使用イメージ削除
nerdctl image prune -a -f            # 確認なし

# イメージ情報
nerdctl inspect <image-name>
nerdctl history <image-name>

# イメージ保存/読込
nerdctl save -o myimage.tar <image-name>
nerdctl load -i myimage.tar

# イメージタグ
nerdctl tag <source-image> <target-image>
```

## Registry 操作

```bash
# ログイン
nerdctl login <registry>
nerdctl login -u <user> -p <password> <registry>

# ログアウト
nerdctl logout <registry>

# プッシュ
nerdctl push <image-name>:<tag>
nerdctl push <image-name>:<tag> --insecure-registry

# プル
nerdctl pull <image-name>:<tag>
nerdctl pull <image-name>:<tag> --insecure-registry
```

## コンテナ管理

```bash
# コンテナ起動
nerdctl run -d --name <name> <image>
nerdctl run -it --rm <image> /bin/sh
nerdctl run -p 8080:80 <image>
nerdctl run -v /host/path:/container/path <image>

# コンテナ一覧
nerdctl ps
nerdctl ps -a                        # 停止中も表示

# コンテナ停止/起動/再起動
nerdctl stop <container>
nerdctl start <container>
nerdctl restart <container>

# コンテナ削除
nerdctl rm <container>
nerdctl rm -f <container>            # 強制削除
nerdctl container prune              # 停止コンテナ全削除
nerdctl container prune -f

# コンテナログ
nerdctl logs <container>
nerdctl logs -f <container>          # フォロー
nerdctl logs --tail 100 <container>

# コンテナ内でコマンド実行
nerdctl exec -it <container> /bin/bash
nerdctl exec <container> ls /app

# コンテナ情報
nerdctl inspect <container>
nerdctl stats                        # リソース使用状況
nerdctl top <container>
```

## ボリューム管理

```bash
# ボリューム作成
nerdctl volume create <volume-name>

# ボリューム一覧
nerdctl volume ls

# ボリューム削除
nerdctl volume rm <volume-name>
nerdctl volume prune                 # 未使用ボリューム削除
nerdctl volume prune -f

# ボリューム情報
nerdctl volume inspect <volume-name>
```

## ネットワーク管理

```bash
# ネットワーク作成
nerdctl network create <network-name>

# ネットワーク一覧
nerdctl network ls

# ネットワーク削除
nerdctl network rm <network-name>
nerdctl network prune

# ネットワーク情報
nerdctl network inspect <network-name>
```

## docker-compose 互換（nerdctl compose）

```bash
# ビルド
nerdctl compose build
nerdctl compose build --no-cache

# 起動
nerdctl compose up
nerdctl compose up -d                # デタッチモード

# 停止
nerdctl compose down
nerdctl compose stop

# ログ
nerdctl compose logs
nerdctl compose logs -f

# プッシュ
nerdctl compose push

# プル
nerdctl compose pull

# サービス一覧
nerdctl compose ps
```

## ビルドキャッシュ管理

```bash
# ビルドキャッシュ削除
nerdctl builder prune
nerdctl builder prune -a             # 全キャッシュ削除
nerdctl builder prune -a -f          # 確認なし
```

## システム管理

```bash
# システム情報
nerdctl info
nerdctl version

# ディスク使用状況
nerdctl system df

# 全体クリーンアップ
nerdctl system prune                 # 未使用リソース削除
nerdctl system prune -a              # より積極的に削除
nerdctl system prune -a --volumes    # ボリュームも含む
nerdctl system prune -a --volumes -f # 確認なし
```

## デバッグ・トラブルシューティング

```bash
# デバッグモード
nerdctl --debug <command>

# namespace 指定
nerdctl --namespace k8s.io ps        # k8s のコンテナ表示
nerdctl --namespace default ps

# イベント確認
nerdctl events
nerdctl events --filter type=container
```

---

## よく使うワンライナー集

```bash
# 全イメージ削除
nerdctl rmi $(nerdctl images -q) -f

# 停止中のコンテナ全削除
nerdctl rm $(nerdctl ps -aq)

# 完全クリーンアップ
nerdctl system prune -a --volumes -f && nerdctl builder prune -a -f

# イメージサイズ確認
nerdctl images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}"

# 最新10件のコンテナログ
nerdctl logs --tail 10 <container>

# リソース使用率の高いコンテナ
nerdctl stats --no-stream | sort -k3 -rh

# 特定タグのイメージを一括削除
nerdctl images | grep "v1" | awk '{print $3}' | xargs nerdctl rmi
```

---

## 移行時の注意点

| 項目 | localhost | リモートホスト |
|------|-----------|----------------|
| **URL** | `localhost:5000/image:tag` | `registry.example.com:5000/image:tag` |
| **TLS** | 不要 | 推奨（Let's Encrypt or 自己署名） |
| **ファイアウォール** | 不要 | ポート5000開放必要 |
| **認証** | オプション | 推奨 |
| **証明書配布** | 不要 | 全クライアントに配布 |
| **DNS** | 不要 | 必要（またはIPアドレス） |

何か追加で必要な情報があれば教えてください！