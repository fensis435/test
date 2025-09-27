### Overview
提供する gui-app は Node.js と Express を使った軽量アプリケーションです。ルートとヘルスチェックを提供し、ログを標準出力に出します。デフォルトポートは **8000** で、Kubernetes 上の既存 Envoy 設定と合わせて動作するようにします。

---

### Source files
- ファイル構成
  - package.json
  - app.js
  - Dockerfile
  - .dockerignore

- package.json
```json
{
  "name": "gui-app",
  "version": "1.0.0",
  "description": "Simple GUI app for Envoy reverse proxy",
  "main": "app.js",
  "scripts": {
    "start": "node app.js"
  },
  "dependencies": {
    "express": "^4.18.2",
    "morgan": "^1.10.0"
  }
}
```

- app.js
```javascript
const express = require("express");
const morgan = require("morgan");

const app = express();
const PORT = process.env.PORT || 8000;

app.use(morgan("dev"));

app.get("/", (req, res) => {
  res.type("text/plain").send("Hello from GUI");
});

app.get("/health", (req, res) => {
  res.type("text/plain").send("ok");
});

app.listen(PORT, "0.0.0.0", () => {
  console.log(`GUI app listening on port ${PORT}`);
});
```

- Dockerfile
```dockerfile
FROM node:18-slim
ENV NODE_ENV=production
WORKDIR /app

COPY package.json package-lock.json* /app/
RUN npm ci --only=production

COPY app.js /app/

EXPOSE 8000
USER 1000
CMD ["node", "app.js"]
```

- .dockerignore
```
node_modules
npm-debug.log
Dockerfile
.git
```

---

### Build and run locally
- ローカル Docker ビルドと実行
```bash
# ビルド
docker build -t gui-app:local .

# 実行して確認
docker run --rm -p 8000:8000 gui-app:local

# 別ターミナルで確認
curl -v http://127.0.0.1:8000/
curl -v http://127.0.0.1:8000/health
```
- イメージを minikube に直接使う場合は次を実行してからビルド
```bash
eval $(minikube docker-env)
docker build -t gui-app:latest .
# Kubernetes Deployment が imagePullPolicy IfNotPresent の場合、再起動で反映
kubectl rollout restart deployment/gui-deployment
kubectl rollout status deployment/gui-deployment
```

---

### Push to registry
- Docker Hub など外部レジストリにプッシュする手順
```bash
# タグ付け
docker tag gui-app:local <YOUR_REGISTRY>/gui-app:latest

# プッシュ
docker push <YOUR_REGISTRY>/gui-app:latest

# Kubernetes Deployment を更新
kubectl set image deployment/gui-deployment gui-app=<YOUR_REGISTRY>/gui-app:latest
kubectl rollout status deployment/gui-deployment
```
- **Replace** `<YOUR_REGISTRY>` with your registry name or Docker Hub user.

---

### Update Kubernetes Deployment
- 既存 manifest を使う場合の image 修正例
```yaml
# 部分抜粋
containers:
- name: gui-app
  image: gui-app:latest
  imagePullPolicy: IfNotPresent
  ports:
  - containerPort: 8000
```
- コマンドで差分反映
```bash
kubectl apply -f gui-deployment-service.yaml
kubectl rollout restart deployment/gui-deployment
kubectl rollout status deployment/gui-deployment
```
- 動作確認
```bash
kubectl get pods -l app=gui -o wide
kubectl logs -l app=gui --tail=200
# Envoy 経由確認
export MINIKUBE_IP=$(minikube ip)
curl -v -H "Host: test.dev.local" http://${MINIKUBE_IP}/
```

---

### Notes and tips
- **Port** は 8000 を想定しています。Envoy の gui_service が 127.0.0.1:8000 に向けている場合、Deployment 内でコンテナ名やポート設定を合わせてください。  
- **Health endpoint** を readiness probe と liveness probe に利用してください。  
- Minikube を使う場合、イメージを外部レジストリに push しなくてもビルド済イメージをそのまま使用できます。  
- 問題が出たら `kubectl logs` と `kubectl describe pod` を確認し、Envoy との接続ログも参照してください。
