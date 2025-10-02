### 概要

Minikube 上の Ingress（nginx）経由で外部からアクセスできるよう、ローカル BIND9 にワイルドカードサブドメインを登録してルーティングする実践的な手順を示します。  
ポイントは次の通りです。  
- BIND9 にゾーンを作り *.example.local を minikube の IP に向ける  
- Minikube の Ingress を「*.example.local」をホストとして受けるようにする  
- 既存の Envoy サイドカー構成（GUI Pod）をそのまま使う

---

### 前提

- 実行ホストは Ubuntu（root または sudo 権限あり）  
- Minikube と kubectl が動作している  
- Ingress アドオンが有効（minikube addons enable ingress）  
- 既に構築済みの Kubernetes マニフェスト（GUI + Envoy サイドカー、SubWeb）を使う想定  
- BIND9 がローカル DNS サーバとして動かせる（ポート 53 を使える）

環境変数（最初に実行）：
```bash
export IP=$(minikube ip)
# 例: IP=192.168.49.2
```

---

### BIND9 設定

1. BIND9 のインストールと基本設定
```bash
sudo apt update
sudo apt install -y bind9 bind9utils
```

2. ゾーン用ディレクトリ作成
```bash
sudo mkdir -p /etc/bind/zones
sudo chown -R root:root /etc/bind/zones
```

3. named.conf.local にゾーン定義を追加
`/etc/bind/named.conf.local` を編集して次を追加します（zone 名は example.local にしています。運用に合わせて変更可）：

```text
zone "example.local" {
    type master;
    file "/etc/bind/zones/db.example.local";
    allow-update { none; };
};
```

4. ゾーンファイルを作成（/etc/bind/zones/db.example.local）
`$IP` を実際の minikube IP に置き換えて作成します：

```bash
sudo tee /etc/bind/zones/db.example.local > /dev/null <<EOF
\$TTL 600
@    IN SOA  ns.example.local. admin.example.local. (
             2025092701 ; serial
             600        ; refresh
             120        ; retry
             604800     ; expire
             600 )      ; minimum
;
@           IN NS    ns.example.local.
ns          IN A     ${IP}
@           IN A     ${IP}
*           IN A     ${IP}
EOF
```

ポイント
- `@`（ゾーン apex）と `*`（ワイルドカード）を minikube IP に向けています。  
- `ns.example.local.` はローカルネームサーバ名で自由に設定可。

5. BIND9 を再起動して設定反映
```bash
sudo systemctl restart bind9
sudo systemctl status bind9
```

6. システムの DNS をローカル BIND に向ける（開発環境向け）
- 一時的に現在のセッションだけ変更する（効果はその端末のみ）：
```bash
sudo nmcli dev show | grep DNS || true
# 確認後、/etc/resolv.conf を編集しない方針なら下は代替手順
sudo sed -i '1i nameserver 127.0.0.1' /etc/resolv.conf
```
- 永続的には NetworkManager の設定や /etc/systemd/resolved.conf を修正して 127.0.0.1 を優先 DNS にしてください。  
- 代替：クライアントマシンから dig を使う場合は `dig @127.0.0.1 test.example.local` のように明示的に DNS サーバを指定してテスト可能。

7. 動作確認
```bash
dig @127.0.0.1 test.example.local A +short
# 出力に minikube IP が返れば OK
```

---

### Kubernetes 側設定（Ingress にワイルドカードを使う）

1. Ingress をワイルドカードホストにする  
Ingress YAML の host を `*.example.local` にしておきます（Ingress controller によりワイルドカード対応の挙動が若干変わる点に注意）：

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: wildcard-ingress
  annotations:
    kubernetes.io/ingress.class: nginx
spec:
  rules:
  - host: "*.example.local"
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: gui-service
            port:
              number: 80
```

2. 既存の GUI Deployment / Envoy Config はそのまま使う  
- Envoy サイドカーは Ingress から来た Host ヘッダを参照してルーティングする（今回 GUI が受け口）  
- Envoy の route_config で `domains: ["*"]` や Host ベースのマッチを使っているなら問題なし

3. 注意点
- 一部の Ingress controller（古いものや特定設定）ではワイルドカードホストは TLS 証明書処理などで制限があるため、Ingress の version/annotation を確認してください。nginx-ingress はワイルドカード host を許容します。  
- Ingress の Status に `IP` が正しく入るか `kubectl get ingress` で確認してください。BIND 側の A レコードは minikube IP を向けているため整合します。

---

### デプロイ手順まとめ（コマンド順で）

1. 環境変数
```bash
export IP=$(minikube ip)
```

2. Minikube 内でイメージビルド
```bash
eval $(minikube docker-env)
docker build -t gui-app:latest ./gui
docker build -t subweb-flask:latest ./subweb
# 元のシェルに戻すには: eval $(minikube docker-env -u)
```

3. BIND9 のゾーン作成（上の手順を実行）
```bash
# 既に示したコマンド群を実行
# /etc/bind/zones/db.example.local を作成し restart bind9
```

4. Kubernetes リソース適用
```bash
kubectl apply -f envoy-gui-config.yaml
kubectl apply -f subweb-deployment.yaml
kubectl apply -f gui-deployment.yaml
# wildcard-ingress.yaml 内の host が "*.example.local" になっていることを確認してから
kubectl apply -f wildcard-ingress.yaml
```

5. GUI Deployment を再起動して Envoy が新 Config を拾う
```bash
kubectl rollout restart deployment/gui-deployment
kubectl rollout status deployment/gui-deployment
```

---

### 動作確認

1. DNS 解決テスト
```bash
dig @127.0.0.1 test.example.local A +short
# => should print ${IP}
```

2. HTTP テスト（Host ヘッダで指定）
```bash
# ブラウザから http://test.example.local/ にアクセス（システムDNSが127.0.0.1を使う場合）
# または curl を使う場合
curl -H "Host: test.example.local" http://${IP}/
curl -H "Host: test.example.local" http://${IP}/subweb
```

3. Socket.IO テスト
```bash
# polling handshake
curl -i "http://test.example.local/subweb/socket.io/?EIO=4&transport=polling"

# websocket (wscat)
wscat -c "ws://test.example.local/subweb/socket.io/?EIO=4&transport=websocket"

# node client
export IP=$(minikube ip)
node test-client.js
```

4. 問題切り分けコマンド
```bash
kubectl get ingress
kubectl get svc
kubectl get pods -o wide
kubectl get endpoints gui-service subweb-service
kubectl logs <gui-pod> -c envoy
kubectl logs deployment/subweb-deployment
# Envoy admin config
kubectl exec -it <gui-pod> -c envoy -- curl -sS http://127.0.0.1:9901/config_dump | jq '.'
```

---

### 補足と運用上の注意

- DNS の TTL を小さめ（例 600）にしておくと minikube IP 変更時に切り替えやすい。  
- 複数クライアント端末がある場合は各端末の DNS 設定をローカル BIND に向けるか、社内 DNS にゾーンを追加してください。  
- 本番でワイルドカード TLS を使う場合はワイルドカード証明書を用意し、Ingress TLS セクションで secret を指定します。  
- セキュリティ: 開発用のローカル BIND を外部公開しないでください。bind9 は必要なネットワーク範囲のみからのクエリを許可する設定にするかファイアウォールで保護してください。  
- minikube の IP が変わると BIND の A レコードを更新する必要があります。自動化するならスクリプトで `minikube ip` を取得して zone ファイルを書き換え、bind9 を reload するフローを作ってください。

---

### 概要

以下はローカル BIND9 にワイルドカードゾーンを作成し、Minikube 上で Envoy サイドカーを使う GUI Pod が Ingress 経由で外部アクセスを受け取り、/subweb の HTTP と Socket.IO を Sub Web にプロキシするための完全なファイル群と手順です。
- ドメインは **example.local** を使います。必要であれば別ドメインに置換してください。
- Minikube IP は環境変数 **IP** にセットして使います。

---

### 1 BIND9 の設定ファイル

- ファイル 1 named.conf.local 追記内容
```conf
zone "example.local" {
    type master;
    file "/etc/bind/zones/db.example.local";
    allow-update { none; };
};
```

- ファイル 2 ゾーンファイル /etc/bind/zones/db.example.local
```dns
$TTL 600
@    IN SOA  ns.example.local. admin.example.local. (
             2025092701 ; serial
             600        ; refresh
             120        ; retry
             604800     ; expire
             600 )      ; minimum
;
@           IN NS    ns.example.local.
ns          IN A     ${IP}
@           IN A     ${IP}
*           IN A     ${IP}
```
- BIND9 再起動コマンド
```bash
# IP をセットしてから実行
export IP=$(minikube ip)
sudo mkdir -p /etc/bind/zones
sudo tee /etc/bind/zones/db.example.local > /dev/null <<EOF
$TTL 600
@    IN SOA  ns.example.local. admin.example.local. (
             2025092701 ; serial
             600        ; refresh
             120        ; retry
             604800     ; expire
             600 )      ; minimum
;
@           IN NS    ns.example.local.
ns          IN A     ${IP}
@           IN A     ${IP}
*           IN A     ${IP}
EOF
# named.conf.local に zone エントリを追加済みであれば reload
sudo systemctl restart bind9
sudo systemctl status bind9
# テスト
dig @127.0.0.1 test.example.local A +short
```

---

### 2 Kubernetes ConfigMap Envoy 設定

ファイル envoy-gui-config.yaml
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: envoy-gui-config
data:
  envoy.yaml: |
    static_resources:
      listeners:
      - name: listener_0
        address:
          socket_address: { address: 0.0.0.0, port_value: 8080 }
        filter_chains:
        - filters:
          - name: envoy.filters.network.http_connection_manager
            typed_config:
              "@type": type.googleapis.com/envoy.extensions.filters.network.http_connection_manager.v3.HttpConnectionManager
              stat_prefix: ingress_http
              codec_type: AUTO
              upgrade_configs:
              - upgrade_type: websocket
              route_config:
                name: local_route
                virtual_hosts:
                - name: backend
                  domains: ["*"]
                  routes:
                  - match: { prefix: "/subweb/socket.io" }
                    route: { cluster: subweb_service, idle_timeout: 1h }
                  - match: { prefix: "/subweb" }
                    route: { cluster: subweb_service, idle_timeout: 1h }
                  - match: { prefix: "/" }
                    route: { cluster: gui_service }
              http_filters:
              - name: envoy.filters.http.router
                typed_config:
                  "@type": type.googleapis.com/envoy.extensions.filters.http.router.v3.Router
      clusters:
      - name: gui_service
        connect_timeout: 0.5s
        type: STATIC
        lb_policy: ROUND_ROBIN
        load_assignment:
          cluster_name: gui_service
          endpoints:
          - lb_endpoints:
            - endpoint:
                address:
                  socket_address: { address: 127.0.0.1, port_value: 8000 }
      - name: subweb_service
        connect_timeout: 0.5s
        type: STRICT_DNS
        lb_policy: ROUND_ROBIN
        load_assignment:
          cluster_name: subweb_service
          endpoints:
          - lb_endpoints:
            - endpoint:
                address:
                  socket_address:
                    address: subweb-service.default.svc.cluster.local
                    port_value: 80
    admin:
      access_log_path: "/tmp/admin_access.log"
      address:
        socket_address: { address: 127.0.0.1, port_value: 9901 }
```

---

### 3 Kubernetes Deployment と Service と Ingress

- ファイル gui-deployment.yaml
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: gui-deployment
spec:
  replicas: 1
  selector:
    matchLabels:
      app: gui
  template:
    metadata:
      labels:
        app: gui
    spec:
      containers:
      - name: envoy
        image: envoyproxy/envoy:v1.24.1
        imagePullPolicy: IfNotPresent
        ports:
        - containerPort: 8080
        volumeMounts:
        - name: envoy-config
          mountPath: /etc/envoy
      - name: gui-app
        image: gui-app:latest
        imagePullPolicy: IfNotPresent
        ports:
        - containerPort: 8000
      volumes:
      - name: envoy-config
        configMap:
          name: envoy-gui-config
---
apiVersion: v1
kind: Service
metadata:
  name: gui-service
spec:
  selector:
    app: gui
  ports:
  - port: 80
    targetPort: 8080
```

- ファイル subweb-deployment.yaml
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: subweb-deployment
spec:
  replicas: 1
  selector:
    matchLabels:
      app: subweb
  template:
    metadata:
      labels:
        app: subweb
    spec:
      containers:
      - name: subweb
        image: subweb-flask:latest
        imagePullPolicy: IfNotPresent
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: subweb-service
spec:
  selector:
    app: subweb
  ports:
  - port: 80
    targetPort: 80
```

- ファイル wildcard-ingress.yaml
注意 Ingress host を **example.local** に合わせています
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: wildcard-ingress
  annotations:
    kubernetes.io/ingress.class: nginx
spec:
  rules:
  - host: "*.example.local"
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: gui-service
            port:
              number: 80
```

---

### 4 アプリケーションファイルと Dockerfile

- gui/Dockerfile
```dockerfile
FROM node:16-alpine
WORKDIR /app
COPY package.json ./
RUN npm install
COPY app.js ./
EXPOSE 8000
CMD ["node","app.js"]
```

- gui/package.json
```json
{
  "name": "gui-app",
  "version": "1.0.0",
  "dependencies": {
    "express": "^4.17.1"
  }
}
```

- gui/app.js
```js
const express = require('express');
const app = express();
app.get('/', (_, res) => res.send('Hello from GUI'));
app.listen(8000, () => console.log('GUI listening on 8000'));
```

- subweb/Dockerfile
```dockerfile
FROM python:3.9-slim
RUN pip install flask flask-socketio eventlet
COPY app.py /app.py
EXPOSE 80
CMD ["python","/app.py"]
```

- subweb/app.py
```python
from flask import Flask
from flask_socketio import SocketIO, send

app = Flask(__name__)
# Envoy forwards /subweb/* as-is so set Socket.IO path accordingly
socketio = SocketIO(app, cors_allowed_origins="*", path="/subweb/socket.io")

@app.route("/subweb")
def index():
    return "Hello from Sub Web"

@socketio.on('message', namespace='/')
def handle(msg):
    send(f"Echo: {msg}")

if __name__ == "__main__":
    socketio.run(app, host="0.0.0.0", port=80)
```

---

### 5 テストクライアントとヘルパースクリプト

- ファイル test-client.js
```js
const { io } = require("socket.io-client");
const ip = process.env.IP || "127.0.0.1";
const url = `http://test.${ip}.nip.io`;
const socket = io(url, { path: "/subweb/socket.io" });

socket.on("connect", () => console.log("connected", socket.id));
socket.on("connect_error", (err) => console.error("connect_error", err));
socket.on("message", (m) => console.log("msg", m));
socket.on("disconnect", (reason) => console.log("disconnected", reason));
```

- wscat 用接続例
```bash
wscat -c "ws://test.${IP}.example.local/subweb/socket.io/?EIO=4&transport=websocket"
```

- Engine.IO ポーリングハンドシェイク確認
```bash
curl -i "http://test.${IP}.example.local/subweb/socket.io/?EIO=4&transport=polling"
```

---

### 6 展開手順と検証コマンド

1. Minikube 起動と ingress 有効化
```bash
minikube start
minikube addons enable ingress
export IP=$(minikube ip)
```

2. Minikube 内の Docker に切替えてイメージビルド
```bash
eval $(minikube docker-env)
docker build -t gui-app:latest ./gui
docker build -t subweb-flask:latest ./subweb
# 元の環境に戻す場合:
# eval $(minikube docker-env -u)
```

3. BIND9 ゾーン作成と再起動（前節の zone ファイル作成を参照）
```bash
# zone ファイルを作成してから
sudo systemctl restart bind9
```

4. Kubernetes リソース適用
```bash
kubectl apply -f envoy-gui-config.yaml
kubectl apply -f subweb-deployment.yaml
kubectl apply -f gui-deployment.yaml
kubectl apply -f wildcard-ingress.yaml
kubectl rollout restart deployment/gui-deployment
kubectl rollout status deployment/gui-deployment
```

5. DNS と HTTP の確認
```bash
# ローカル DNS に問い合わせ
dig @127.0.0.1 test.example.local A +short

# HTTP
curl -H "Host: test.example.local" http://${IP}/
curl -H "Host: test.example.local" http://${IP}/subweb
```

6. Socket.IO の接続確認
```bash
# wscat
wscat -c "ws://test.${IP}.example.local/subweb/socket.io/?EIO=4&transport=websocket"

# Node client
export IP=$(minikube ip)
npm install socket.io-client
node test-client.js
```

7. トラブルシューティングコマンド
```bash
kubectl get pods -o wide
kubectl get svc
kubectl get endpoints gui-service subweb-service
kubectl get ingress
kubectl logs deployment/subweb-deployment --tail=200
kubectl logs -l app=gui -c envoy --tail=200
# Envoy の実設定確認
kubectl get pods -l app=gui -o name
kubectl exec -it $(kubectl get pods -l app=gui -o jsonpath='{.items[0].metadata.name}') -c envoy -- curl -sS http://127.0.0.1:9901/config_dump | jq '.'
```

---

### 補足運用ノート

- **DNS の優先順** を変えずに動作確認するには `dig @127.0.0.1 test.example.local` のように DNS サーバを明示してテストしてください。
- Minikube の IP が変わるたびに BIND ゾーンの A レコードを更新する必要があります。自動化スクリプトを用意することを推奨します.
- 本番用の TLS を使う場合は wildcard 証明書を Ingress に設定してください。
- Socket.IO を複数レプリカで運用する場合は Redis Adapter を導入してください。

---

### 概要

下記はすべてを1つにまとめた tar アーカイブを作成するコマンドと、Minikube 上へ自動展開するスクリプトおよびクリーンアップスクリプトの完全版です。
- **出力ファイル**: enjov_test.tar.gz（プロジェクト一式）
- **自動化スクリプト**: deploy.sh（作成、ビルド、BIND ゾーン登録、Kubernetes 適用まで実行）
- **クリーンアップ**: cleanup.sh（Kubernetes 削除、BIND ゾーン削除、ローカルファイル削除）

---

### ファイル構成

- enjov_test/
  - gui/Dockerfile
  - gui/package.json
  - gui/app.js
  - subweb/Dockerfile
  - subweb/app.py
  - envoy-gui-config.yaml
  - gui-deployment.yaml
  - subweb-deployment.yaml
  - wildcard-ingress.yaml
  - test-client.js
  - deploy.sh
  - cleanup.sh

---

### 一発で tar を作るコマンド

作業ディレクトリが ~/enjov_test の場合は次のコマンドでアーカイブを作成します。

```bash
# 作業ディレクトリの一段上に移動して実行する例
cd ~/enjov_test/..
tar -czf enjov_test.tar.gz enjov_test
ls -lh enjov_test.tar.gz
```

---

### deploy.sh 自動展開スクリプト

下記をファイル名 deploy.sh として保存して実行権を与えてください。スクリプトは Minikube の Docker に切り替えてイメージをビルドします。BIND9 のゾーン登録は sudo を使用します。実行前に Minikube と kubectl が動作していることを確認してください。

```bash
#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
IP="$(minikube ip)"
ZONE_DIR="/etc/bind/zones"
ZONE_FILE="${ZONE_DIR}/db.example.local"
NAMED_CONF="/etc/bind/named.conf.local"
INGRESS_HOST="*.example.local"

echo "Project dir: ${PROJECT_DIR}"
echo "Minikube IP: ${IP}"

# 1 Generate files if not present
cat > "${PROJECT_DIR}/gui/Dockerfile" <<'DOCK'
FROM node:16-alpine
WORKDIR /app
COPY package.json ./
RUN npm install
COPY app.js ./
EXPOSE 8000
CMD ["node","app.js"]
DOCK

cat > "${PROJECT_DIR}/gui/package.json" <<'JSON'
{
  "name": "gui-app",
  "version": "1.0.0",
  "dependencies": {
    "express": "^4.17.1"
  }
}
JSON

cat > "${PROJECT_DIR}/gui/app.js" <<'JS'
const express = require('express');
const app = express();
app.get('/', (_, res) => res.send('Hello from GUI'));
app.listen(8000, () => console.log('GUI listening on 8000'));
JS

cat > "${PROJECT_DIR}/subweb/Dockerfile" <<'DOCK'
FROM python:3.9-slim
RUN pip install --no-cache-dir flask flask-socketio eventlet
COPY app.py /app.py
EXPOSE 80
CMD ["python","/app.py"]
DOCK

cat > "${PROJECT_DIR}/subweb/app.py" <<'PY'
from flask import Flask
from flask_socketio import SocketIO, send

app = Flask(__name__)
socketio = SocketIO(app, cors_allowed_origins="*", path="/subweb/socket.io")

@app.route("/subweb")
def index():
    return "Hello from Sub Web"

@socketio.on('message', namespace='/')
def handle(msg):
    send(f"Echo: {msg}")

if __name__ == "__main__":
    socketio.run(app, host="0.0.0.0", port=80)
PY

cat > "${PROJECT_DIR}/envoy-gui-config.yaml" <<'YAML'
apiVersion: v1
kind: ConfigMap
metadata:
  name: envoy-gui-config
data:
  envoy.yaml: |
    static_resources:
      listeners:
      - name: listener_0
        address:
          socket_address: { address: 0.0.0.0, port_value: 8080 }
        filter_chains:
        - filters:
          - name: envoy.filters.network.http_connection_manager
            typed_config:
              "@type": type.googleapis.com/envoy.extensions.filters.network.http_connection_manager.v3.HttpConnectionManager
              stat_prefix: ingress_http
              codec_type: AUTO
              upgrade_configs:
              - upgrade_type: websocket
              route_config:
                name: local_route
                virtual_hosts:
                - name: backend
                  domains: ["*"]
                  routes:
                  - match: { prefix: "/subweb/socket.io" }
                    route: { cluster: subweb_service, idle_timeout: 1h }
                  - match: { prefix: "/subweb" }
                    route: { cluster: subweb_service, idle_timeout: 1h }
                  - match: { prefix: "/" }
                    route: { cluster: gui_service }
              http_filters:
              - name: envoy.filters.http.router
                typed_config:
                  "@type": type.googleapis.com/envoy.extensions.filters.http.router.v3.Router

      clusters:
      - name: gui_service
        connect_timeout: 0.5s
        type: STATIC
        lb_policy: ROUND_ROBIN
        load_assignment:
          cluster_name: gui_service
          endpoints:
          - lb_endpoints:
            - endpoint:
                address:
                  socket_address: { address: 127.0.0.1, port_value: 8000 }
      - name: subweb_service
        connect_timeout: 0.5s
        type: STRICT_DNS
        lb_policy: ROUND_ROBIN
        load_assignment:
          cluster_name: subweb_service
          endpoints:
          - lb_endpoints:
            - endpoint:
                address:
                  socket_address:
                    address: subweb-service.default.svc.cluster.local
                    port_value: 80
    admin:
      access_log_path: "/tmp/admin_access.log"
      address:
        socket_address: { address: 127.0.0.1, port_value: 9901 }
YAML

cat > "${PROJECT_DIR}/gui-deployment.yaml" <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: gui-deployment
spec:
  replicas: 1
  selector:
    matchLabels:
      app: gui
  template:
    metadata:
      labels:
        app: gui
    spec:
      containers:
      - name: envoy
        image: envoyproxy/envoy:v1.24.1
        imagePullPolicy: IfNotPresent
        ports:
        - containerPort: 8080
        volumeMounts:
        - name: envoy-config
          mountPath: /etc/envoy
      - name: gui-app
        image: gui-app:latest
        imagePullPolicy: IfNotPresent
        ports:
        - containerPort: 8000
      volumes:
      - name: envoy-config
        configMap:
          name: envoy-gui-config
---
apiVersion: v1
kind: Service
metadata:
  name: gui-service
spec:
  selector:
    app: gui
  ports:
  - port: 80
    targetPort: 8080
YAML

cat > "${PROJECT_DIR}/subweb-deployment.yaml" <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: subweb-deployment
spec:
  replicas: 1
  selector:
    matchLabels:
      app: subweb
  template:
    metadata:
      labels:
        app: subweb
    spec:
      containers:
      - name: subweb
        image: subweb-flask:latest
        imagePullPolicy: IfNotPresent
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: subweb-service
spec:
  selector:
    app: subweb
  ports:
  - port: 80
    targetPort: 80
YAML

cat > "${PROJECT_DIR}/wildcard-ingress.yaml" <<'YAML'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: wildcard-ingress
  annotations:
    kubernetes.io/ingress.class: nginx
spec:
  rules:
  - host: "*.example.local"
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: gui-service
            port:
              number: 80
YAML

cat > "${PROJECT_DIR}/test-client.js" <<'JS'
const { io } = require("socket.io-client");
const ip = process.env.IP || "127.0.0.1";
const url = `http://test.${ip}.nip.io`;
const socket = io(url, { path: "/subweb/socket.io" });

socket.on("connect", () => console.log("connected", socket.id));
socket.on("connect_error", (err) => console.error("connect_error", err));
socket.on("message", (m) => console.log("msg", m));
socket.on("disconnect", (reason) => console.log("disconnected", reason));
JS

# 2 Build images inside minikube docker
echo "Building Docker images inside minikube"
eval "$(minikube docker-env)"
docker build -t gui-app:latest "${PROJECT_DIR}/gui"
docker build -t subweb-flask:latest "${PROJECT_DIR}/subweb"

# 3 Ensure namespace and apply manifests
kubectl apply -f "${PROJECT_DIR}/envoy-gui-config.yaml"
kubectl apply -f "${PROJECT_DIR}/subweb-deployment.yaml"
kubectl apply -f "${PROJECT_DIR}/gui-deployment.yaml"
kubectl apply -f "${PROJECT_DIR}/wildcard-ingress.yaml"

# 4 Create BIND zone as root
if [ "$(id -u)" -ne 0 ]; then
  echo "Creating BIND zone requires sudo. Re-run this script with sudo or enter password."
fi

sudo mkdir -p "${ZONE_DIR}"
sudo tee "${ZONE_FILE}" > /dev/null <<EOF
\$TTL 600
@    IN SOA  ns.example.local. admin.example.local. (
             2025092701 ; serial
             600        ; refresh
             120        ; retry
             604800     ; expire
             600 )      ; minimum
;
@           IN NS    ns.example.local.
ns          IN A     ${IP}
@           IN A     ${IP}
*           IN A     ${IP}
EOF

# Append zone to named.conf.local if not present
if ! grep -q 'zone "example.local"' "${NAMED_CONF}"; then
  sudo tee -a "${NAMED_CONF}" > /dev/null <<EOF

zone "example.local" {
    type master;
    file "/etc/bind/zones/db.example.local";
    allow-update { none; };
};
EOF
fi

sudo systemctl restart bind9
sleep 2
echo "BIND restarted. DNS test:"
dig @127.0.0.1 test.example.local A +short

# 5 Restart GUI to pick up config
kubectl rollout restart deployment/gui-deployment
kubectl rollout status deployment/gui-deployment

echo "Deploy complete. Test endpoints:"
echo "HTTP GUI: curl -H 'Host: test.example.local' http://${IP}/"
echo "HTTP Subweb: curl -H 'Host: test.example.local' http://${IP}/subweb"
echo "SocketIO test: wscat -c 'ws://test.${IP}.example.local/subweb/socket.io/?EIO=4&transport=websocket'"
```

付与実行権と実行手順

```bash
chmod +x deploy.sh
./deploy.sh
```

---

### cleanup.sh クリーンアップスクリプト

下記を cleanup.sh として保存して実行してください。Kubernetes リソースを削除し BIND ゾーンを元に戻します。

```bash
#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
ZONE_DIR="/etc/bind/zones"
ZONE_FILE="${ZONE_DIR}/db.example.local"
NAMED_CONF="/etc/bind/named.conf.local"

echo "Deleting Kubernetes resources"
kubectl delete -f "${PROJECT_DIR}/wildcard-ingress.yaml" --ignore-not-found
kubectl delete -f "${PROJECT_DIR}/gui-deployment.yaml" --ignore-not-found
kubectl delete -f "${PROJECT_DIR}/subweb-deployment.yaml" --ignore-not-found
kubectl delete -f "${PROJECT_DIR}/envoy-gui-config.yaml" --ignore-not-found

echo "Removing BIND zone files"
if [ -f "${ZONE_FILE}" ]; then
  sudo rm -f "${ZONE_FILE}"
fi

# Remove zone entry from named.conf.local if present
if grep -q 'zone "example.local"' "${NAMED_CONF}"; then
  sudo cp "${NAMED_CONF}" "${NAMED_CONF}.bak"
  sudo awk 'BEGIN{skip=0} /zone "example.local"/{skip=1} skip && /};/ {skip=0; next} !skip{print}' "${NAMED_CONF}.bak" | sudo tee "${NAMED_CONF}" > /dev/null
fi

sudo systemctl restart bind9
echo "Cleanup complete"
```

実行手順

```bash
chmod +x cleanup.sh
./cleanup.sh
```

---

### 実行後の検証コマンド

```bash
# DNS
dig @127.0.0.1 test.example.local A +short

# Pods
kubectl get pods -o wide

# Endpoints
kubectl get endpoints gui-service subweb-service

# HTTP
curl -H "Host: test.example.local" http://${IP}/
curl -H "Host: test.example.local" http://${IP}/subweb

# Socket.IO
wscat -c "ws://test.${IP}.example.local/subweb/socket.io/?EIO=4&transport=websocket"
node test-client.js
```

---
