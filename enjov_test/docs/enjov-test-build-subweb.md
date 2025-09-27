### 概要
subweb 用の修正後イメージは Flask?SocketIO を eventlet で起動し **logger** と **engineio_logger** を有効化して WebSocket の接続ログを詳細に出力する構成です。Envoy 経由の WebSocket Upgrade を想定したパス設定 **/subweb** と **/subweb/socket.io** を維持します。

---

### ファイル一覧と内容
- **Dockerfile**
```dockerfile
FROM python:3.9-slim
ENV PYTHONUNBUFFERED=1
WORKDIR /app
COPY requirements.txt /app/
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py /app/
EXPOSE 80
USER 1000
CMD ["python", "/app.py"]
```

- **requirements.txt**
```
flask==2.2.5
flask-socketio==5.3.5
eventlet==0.33.3
```

- **app.py**
```python
from flask import Flask, request
from flask_socketio import SocketIO, send
import logging

logging.basicConfig(level=logging.DEBUG, format="%(asctime)s %(levelname)s %(message)s")
app = Flask(__name__)
socketio = SocketIO(app, cors_allowed_origins="*", path="/subweb/socket.io", logger=True, engineio_logger=True, async_mode="eventlet")

@app.route("/subweb")
def index():
    return "Hello from Sub Web", 200

@app.route("/health")
def health():
    return "ok", 200

@socketio.on("connect")
def on_connect():
    app.logger.info("socket connected client %s", request.sid)

@socketio.on("disconnect")
def on_disconnect():
    app.logger.info("socket disconnected client %s", request.sid)

@socketio.on("message")
def on_message(msg):
    app.logger.debug("received message %s from %s", msg, request.sid)
    send("Echo: " + str(msg))

if __name__ == "__main__":
    socketio.run(app, host="0.0.0.0", port=80)
```

---

### Docker イメージのビルド方法（ローカル Docker）
1. ソースを作業ディレクトリに保存する。
2. ビルドコマンドを実行する。
```bash
docker build -t subweb-flask:latest .
```
3. ローカルで動作確認する。
```bash
docker run --rm -p 8080:80 subweb-flask:latest
# ホスト側で確認
curl -v http://127.0.0.1:8080/subweb
```

---

### Minikube 上でのビルドとデプロイ手順
- Minikube の Docker デーモンを使ってイメージを直接作る。
```bash
eval $(minikube docker-env)
docker build -t subweb-flask:latest .
# デプロイ済みなら rollout restart で新イメージを反映
kubectl rollout restart deployment/subweb-deployment
kubectl rollout status deployment/subweb-deployment
```
- Minikube を使わない場合はコンテナレジストリへタグ付けと push を行い Kubernetes の Deployment を更新する。
```bash
docker tag subweb-flask:latest <registry>/subweb-flask:latest
docker push <registry>/subweb-flask:latest
kubectl set image deployment/subweb-deployment subweb=<registry>/subweb-flask:latest
kubectl rollout status deployment/subweb-deployment
```

---

### Kubernetes 更新後の検証手順
- Pod のローリング再起動状態を確認する。
```bash
kubectl get pods -l app=subweb -o wide
kubectl rollout status deployment/subweb-deployment
```
- ログで Upgrade と sid 発行を確認する。
```bash
kubectl logs -l app=subweb --tail=200
kubectl logs -l app=subweb -f
```
- クライアント検証は socket.io-client を使って行う。
```bash
# ローカルで node ws-test.js を実行して接続を確認する
node ws-test.js
# 簡単な HTTP 確認
curl -v http://<minikube-ip>/subweb -H "Host: test.dev.local"
```
- Envoy 経由の設定を確認する。
```bash
POD=$(kubectl get pod -l app=gui -o jsonpath='{.items[0].metadata.name}')
kubectl port-forward pod/$POD 9901:9901 >/dev/null 2>&1 & echo $! > /tmp/epf.pid
curl -sS http://127.0.0.1:9901/config_dump | jq '.configs[] | .bootstrap.static_resources.listeners[]?.filter_chains[]?.filters[]? | select(.name=="envoy.filters.network.http_connection_manager")'
kill $(cat /tmp/epf.pid) || true; rm -f /tmp/epf.pid
```

---

### 補足と運用上の注意
- **ログ有効化** により upgrade の成功と受信フレームの状況が把握できる。  
- Envoy の codec を HTTP1 に固定すると WebSocket Upgrade の安定性が向上する。ConfigMap の HttpConnectionManager に **codec_type: HTTP1** を追加して apply する。  
- DNS の問題を避けるため Envoy の cluster に FQDN を指定する際は **末尾にドット** を付けるか ClusterIP を直接使う。  
- **テスト時は socket.io-client を検証基準** にする。wscat は Engine.IO 固有の初期フレーミングと互換性の問題が出るため参考値扱いにする。
