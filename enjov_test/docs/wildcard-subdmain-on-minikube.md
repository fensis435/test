### 要点まとめ

- **目的**: Minikube 上でワイルドカードサブドメイン経由に対し GUI Pod の Envoy サイドカーが Ingress からのトラフィックを受け、/subweb の HTTP と Socket.IO を Sub Web に正しくプロキシする構成を再現する手順。  
- **重要な修正点**: Envoy の HTTP フィルタは必ず **typed_config** を付与すること。Envoy でパスを書き換えない場合は Flask-SocketIO 側で **path="/subweb/socket.io"** を指定すること。イメージは Minikube 内でビルドし **imagePullPolicy: IfNotPresent** を使うこと。Socket.IO の接続テストは Engine.IO のクエリを付けて行うこと。  

---

### 前提と準備

- Minikube と kubectl がインストール済み  
- Minikube の ingress アドオンを有効化している  
  ```bash
  minikube start
  minikube addons enable ingress
  ```
- Minikube の Docker デーモンを使ってイメージをビルドする（必須）  
  ```bash
  eval $(minikube docker-env)
  export IP=$(minikube ip)
  ```

---

### ファイル一式

1. GUI イメージ（簡易 Express）
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
{ "name":"gui-app", "version":"1.0.0", "dependencies": { "express": "^4.17.1" } }
```
- gui/app.js
```js
const express = require('express');
const app = express();
app.get('/', (_, res) => res.send('Hello from GUI'));
app.listen(8000, () => console.log('GUI listening on 8000'));
```

2. Sub Web イメージ（Flask + Flask-SocketIO）
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
# Envoy will forward /subweb/* as-is, so specify Socket.IO path accordingly
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

3. Envoy ConfigMap（重要: typed_config と websocket upgrade）
- envoy-gui-config.yaml
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

4. Kubernetes マニフェスト（Deployment/Service/Ingress）
- gui-deployment.yaml
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
- subweb-deployment.yaml
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
- wildcard-ingress.yaml
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: wildcard-ingress
  annotations:
    kubernetes.io/ingress.class: nginx
spec:
  rules:
  - host: "*.${IP}.nip.io"
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

### 展開手順

1. Minikube の Docker 環境に切り替えてイメージをビルド
```bash
eval $(minikube docker-env)
docker build -t gui-app:latest ./gui
docker build -t subweb-flask:latest ./subweb
```

2. ConfigMap とリソースを適用
```bash
kubectl apply -f envoy-gui-config.yaml
kubectl apply -f subweb-deployment.yaml
kubectl apply -f gui-deployment.yaml
# Ingress の host を環境変数に埋めてから適用
export IP=$(minikube ip)
envsubst < wildcard-ingress.yaml | kubectl apply -f -
```

3. GUI Deployment を再起動して Envoy が新設定を拾う
```bash
kubectl rollout restart deployment/gui-deployment
```

---

### 動作確認コマンド

- Pod 状態確認
```bash
kubectl get pods -o wide
```
- Endpoints 確認
```bash
kubectl get endpoints gui-service
kubectl get endpoints subweb-service
```
- HTTP 通常アクセス
```bash
curl -H "Host: test.${IP}.nip.io" http://${IP}/
curl -H "Host: test.${IP}.nip.io" http://${IP}/subweb
```
- Engine.IO ポーリングハンドシェイク確認
```bash
curl -i "http://test.${IP}.nip.io/subweb/socket.io/?EIO=4&transport=polling"
```
- WebSocket 接続テスト（wscat）
```bash
wscat -c "ws://test.${IP}.nip.io/subweb/socket.io/?EIO=4&transport=websocket"
```
- Socket.IO クライアント（node）
```bash
export IP=$(minikube ip)
# ローカルに test-client.js を作成してから
node test-client.js
```
- Envoy 実設定確認
```bash
kubectl get pods -l app=gui -o name
kubectl exec -it <gui-pod> -c envoy -- curl -sS http://127.0.0.1:9901/config_dump | jq '.'
```

---

### トラブルシューティングチェックリスト

- **Envoy が起動できない**: ログで “Didn't find a registered implementation for 'envoy.filters.http.router'” が出ていないか。`http_filters` の router に必ず **typed_config Router** を付与する。  
- **ImagePullBackOff**: イメージは Minikube 内でビルド済みか。Deployment に **imagePullPolicy: IfNotPresent** を付ける。  
- **Ingress で 503**: Ingress の host が正しく展開されているか。`kubectl get ingress` で status.ingress.ip が Minikube IP と一致するか。Service の endpoints が空でないか確認する。  
- **Socket.IO で 404**: wscat ではなく Engine.IO 用クエリを付けて接続する。Envoy の route 順序で `/subweb/socket.io` が `/subweb` より上にあるか確認する。Flask 削除や path のミスマッチがないか確認する。  
- **長時間接続切断**: Envoy の route に **idle_timeout** を長く設定するか Sub Web のタイムアウトを調整する。  
- **スケール時**: Socket.IO を複数レプリカで運用する場合は **Redis Adapter** を導入してセッション共有するか、セッションアフィニティを検討する。  
