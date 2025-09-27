### Summary
追加で **subweb2** として動作する Django サーバを Kubernetes に追加するためのアプリソース、Dockerfile、ビルド手順、Kubernetes マニフェスト、Envoy 設定差分、デプロイと検証手順を示す。

---

### Application Source and Dockerfile
ファイル構成と中身をそのままコピーして作成する。

- requirements.txt
```text
Django==4.2
gunicorn==20.1.0
```

- manage.py and project layout
作業ディレクトリを subweb2 にして以下のツリーを作る:
```
subweb2/
├─ Dockerfile
├─ requirements.txt
├─ manage.py
├─ subweb2project/
│  ├─ __init__.py
│  ├─ settings.py
│  ├─ urls.py
│  ├─ wsgi.py
│  └─ asgi.py
└─ subapp/
   ├─ __init__.py
   ├─ views.py
   └─ urls.py
```

- manage.py
```python
#!/usr/bin/env python
import os
import sys

if __name__ == "__main__":
    os.environ.setdefault("DJANGO_SETTINGS_MODULE", "subweb2project.settings")
    from django.core.management import execute_from_command_line
    execute_from_command_line(sys.argv)
```

- subweb2project/settings.py
```python
from pathlib import Path
BASE_DIR = Path(__file__).resolve().parent.parent
SECRET_KEY = "replace-me"
DEBUG = False
ALLOWED_HOSTS = ["*"]
INSTALLED_APPS = [
    "django.contrib.staticfiles",
    "subapp",
]
MIDDLEWARE = [
    "django.middleware.security.SecurityMiddleware",
    "django.middleware.common.CommonMiddleware",
]
ROOT_URLCONF = "subweb2project.urls"
WSGI_APPLICATION = "subweb2project.wsgi.application"
DATABASES = { "default": { "ENGINE": "django.db.backends.sqlite3", "NAME": BASE_DIR / "db.sqlite3" } }
STATIC_URL = "/static/"
```

- subweb2project/urls.py
```python
from django.urls import path, include
urlpatterns = [
    path("subweb2/", include("subapp.urls")),
    path("health", lambda request: __import__("django.http").http.HttpResponse("ok")),
]
```

- subweb2project/wsgi.py
```python
import os
from django.core.wsgi import get_wsgi_application
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "subweb2project.settings")
application = get_wsgi_application()
```

- subapp/views.py
```python
from django.http import HttpResponse
def index(request):
    return HttpResponse("Hello from subweb2")
```

- subapp/urls.py
```python
from django.urls import path
from .views import index
urlpatterns = [
    path("", index),
]
```

- Dockerfile
```dockerfile
FROM python:3.9-slim
ENV PYTHONUNBUFFERED=1
WORKDIR /app
COPY requirements.txt /app/
RUN pip install --no-cache-dir -r requirements.txt
COPY . /app
EXPOSE 8000
USER 1000
CMD ["gunicorn", "subweb2project.wsgi:application", "--bind", "0.0.0.0:8000", "--workers", "2"]
```

---

### Kubernetes Manifests
保存ファイル名 subweb2-deployment-service.yaml として適用する。

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: subweb2-deployment
  labels:
    app: subweb2
spec:
  replicas: 1
  selector:
    matchLabels:
      app: subweb2
  template:
    metadata:
      labels:
        app: subweb2
    spec:
      containers:
      - name: subweb2
        image: subweb2:latest
        imagePullPolicy: IfNotPresent
        ports:
        - containerPort: 8000
          name: http
        readinessProbe:
          httpGet:
            path: /health
            port: 8000
          initialDelaySeconds: 2
          periodSeconds: 5
        livenessProbe:
          httpGet:
            path: /health
            port: 8000
          initialDelaySeconds: 10
          periodSeconds: 20

---
apiVersion: v1
kind: Service
metadata:
  name: subweb2-service
  labels:
    app: subweb2
spec:
  type: ClusterIP
  ports:
  - name: http
    port: 80
    targetPort: 8000
  selector:
    app: subweb2
```

---

### Envoy ConfigMap Patch
既存 envoy-gui-config の envoy.yaml に以下クラスタと route を追加する。ここでは route の優先順位で /subweb2 を subweb2_service にマップする。

- clusters に追加
```yaml
- name: subweb2_service
  connect_timeout: 0.5s
  type: STRICT_DNS
  lb_policy: ROUND_ROBIN
  dns_lookup_family: V4_ONLY
  load_assignment:
    cluster_name: subweb2_service
    endpoints:
    - lb_endpoints:
      - endpoint:
          address:
            socket_address:
              address: subweb2-service.default.svc.cluster.local.
              port_value: 80
```

- route_config の virtual_hosts.routes に追加するルートを subweb と同列に置く
```yaml
- match: { prefix: "/subweb2" }
  route:
    cluster: subweb2_service
    idle_timeout: 3600s
```

- Envoy の HttpConnectionManager が既に upgrade_configs に websocket を含むなら追加変更は不要。codec_type を HTTP1 に固定済みであることを確認する。

---

### Build Deploy and Verify
1. Minikube 内でビルドする手順
```bash
cd /path/to/subweb2
eval $(minikube docker-env)
docker build -t subweb2:latest .
kubectl apply -f subweb2-deployment-service.yaml
kubectl rollout status deployment/subweb2-deployment
```

2. Envoy ConfigMap を更新して反映する手順
```bash
# 編集後
kubectl apply -f envoy-configmap.yaml
kubectl rollout restart deployment/gui-deployment
kubectl rollout status deployment/gui-deployment
```

3. 確認コマンド
```bash
kubectl get pods -l app=subweb2 -o wide
kubectl get svc subweb2-service -o wide
# Pod 内の HTTP 応答確認
kubectl run --rm -i --tty curl-test --image=curlimages/curl:8.4.0 --restart=Never -- \
  sh -c "curl -sS -D - http://subweb2-service/subweb2/ || true"
# Envoy 経由の外部確認
MINIKUBE_IP=$(minikube ip)
curl -v -H "Host: test.dev.local" http://${MINIKUBE_IP}/subweb2
```

4. ログ確認
```bash
kubectl logs -l app=subweb2 --tail=200
kubectl logs -l app=gui --tail=200
kubectl logs -l app=subweb --tail=200
```

---

### Optional WebSocket Support Using Django Channels
WebSocket 機能が必要な場合は Channels と Daphne を使う手順を実行する。変更点を簡潔に示す。

- requirements.txt に channels と daphne を追加
```
Django==4.2
channels==4.0.0
daphne==4.0.0
gunicorn==20.1.0
```

- subweb2project/asgi.py を Channels 用に作成しルーティングを設定し consumer を実装する。

- Dockerfile の CMD を Daphne に変更
```dockerfile
CMD ["daphne", "-b", "0.0.0.0", "-p", "8000", "subweb2project.asgi:application"]
```

- Envoy の upgrade_configs に websocket が含まれていることを再確認してデプロイする。

---

これで subweb2 を追加するためのソース、Dockerfile、Kubernetes マニフェスト、Envoy 設定差分、ビルドと検証手順を網羅した。必要なら実ファイルを生成するための完全な tarball あるいは差分 YAML を作成する。

---

### 要点
- 現象の原因は Envoy の既存ルート `/subweb` がプレフィックス一致で `/subweb2` を先取りしており、リクエストが **subweb_service** に送られて 404 になっていること。
- 対処は **(1)** subweb2 用の cluster を Envoy に追加し、**(2)** `/subweb2` ルートを `/subweb` より前に置いてマッチ優先度を確保すること。
- さらに安全策として「パス区切りを考慮したマッチ（正規表現）」を使うことを推奨する。

---

### 修正する Envoy ルート方針（要点）
- 文字列プレフィックスだけでなくパス区切りを意識する: 例えば正規表現 `^/subweb2($|/)` を使えば `/subweb2` と `/subweb2/…` のみを捕まえ、`/subweb2foo` や `/subweb` の衝突を避けられる。
- ルートはマッチ優先順で評価されるため、**subweb2 ルートは subweb ルートより前**に置く。

---

### Envoy の差分（追加・挿入すべき YAML 抜粋）
- **clusters** に subweb2 を追加（FQDN に末尾ドットを付けるか clusterIP を使う）:
```yaml
- name: subweb2_service
  connect_timeout: 0.5s
  type: STRICT_DNS
  lb_policy: ROUND_ROBIN
  dns_lookup_family: V4_ONLY
  load_assignment:
    cluster_name: subweb2_service
    endpoints:
    - lb_endpoints:
      - endpoint:
          address:
            socket_address:
              address: subweb2-service.default.svc.cluster.local.
              port_value: 80
```

- **route_config.virtual_hosts[].routes** の先頭に挿入（正規表現マッチを使う例）:
```yaml
- match:
    safe_regex:
      regex: "^/subweb2($|/)"
  route:
    cluster: subweb2_service
    idle_timeout: 3600s

# 既存の subweb2に紐づかないルートはそのまま残すが
# 必ずこのエントリを /subweb や / の前に置く
```

- もし既存 ConfigMap を直接編集するなら `envoy.yaml` の `route_config.virtual_hosts[0].routes` 内の最上位に上記ブロックを追加する。

---

### 適用手順（そのままコピペで実行）
1. 現行 ConfigMap をバックアップする:
```bash
kubectl get configmap envoy-gui-config -o yaml > /tmp/envoy-gui-config.orig.yaml
```
2. local に編集用ファイルを出す:
```bash
kubectl get configmap envoy-gui-config -o jsonpath='{.data.envoy\.yaml}' > /tmp/envoy.yaml
# 編集: /tmp/envoy.yaml の clusters に subweb2 を追加し、
# route_config の routes に safe_regex マッチを subweb より前に挿入する
```
3. 編集済みを ConfigMap に戻す:
```bash
kubectl create configmap envoy-gui-config --from-file=envoy.yaml=/tmp/envoy.yaml -o yaml --dry-run=client | kubectl apply -f -
```
4. Envoy (gui) デプロイを再起動して適用:
```bash
kubectl rollout restart deployment/gui-deployment
kubectl rollout status deployment/gui-deployment
```

---

### 動作確認コマンド
- Envoy 設定が反映されたか確認:
```bash
POD=$(kubectl get pod -l app=gui -o jsonpath='{.items[0].metadata.name}')
kubectl port-forward pod/$POD 9901:9901 >/dev/null 2>&1 & echo $! > /tmp/epf.pid
curl -sS http://127.0.0.1:9901/config_dump > /tmp/envoy_config_dump_after.json
kill $(cat /tmp/epf.pid) || true; rm -f /tmp/epf.pid
# ルートとクラスタがあるか確認
jq '.configs[] | .bootstrap.static_resources.listeners[]?.filter_chains[]?.filters[]? | select(.name=="envoy.filters.network.http_connection_manager") | .typed_config.route_config.virtual_hosts[] | .routes' /tmp/envoy_config_dump_after.json
jq '.configs[] | .bootstrap.static_resources.clusters[]? | select(.name=="subweb2_service")' /tmp/envoy_config_dump_after.json
```
- 外部からアクセスして挙動を見る:
```bash
MINIKUBE_IP=$(minikube ip)
# subweb2 のパス（トレーリング有無の両方で確認）
curl -v -H "Host: test.dev.local" http://${MINIKUBE_IP}/subweb2
curl -v -H "Host: test.dev.local" http://${MINIKUBE_IP}/subweb2/
# subweb（既存）に影響ないかを確認
curl -v -H "Host: test.dev.local" http://${MINIKUBE_IP}/subweb
```
- Pod 側で正しく受信されているかログを確認:
```bash
kubectl logs -l app=subweb2 --tail=200
kubectl logs -l app=subweb --tail=200
kubectl logs -l app=gui --tail=200
```

---

### 追加で確認すべき点と注意
- Django の URL 定義が `path("subweb2/", ...)` の場合、`/subweb2`（末尾なし）への GET は **CommonMiddleware のリダイレクト** によって `/subweb2/` に 301 リダイレクトされるのが標準動作。curl で追跡する際は `-L` を使うか `/subweb2/` を叩くこと。
- Envoy の route マッチは先に定義されたルールが優先されるため、**順序が重要**。必ず `subweb2` を `subweb` より前に入れる。
- もし DNS や cluster 解決を安定化したければ `type: STATIC` で ClusterIP を直接埋める運用も可能（開発時の暫定対応）。

---

これで Envoy 経由で /subweb2 が正しく subweb2-service にルーティングされ、`/subweb` との競合で 404 になる事象が解消される。必要ならあなたの現在の envoy-gui-config を貼ってもらえれば、上の差分をパッチ形式で作成して提示する。

---

### 状況の要約
- envoy-gui-config を適用し gui-deployment を再起動して反映した。
- curl により /subweb も /subweb2/ も Envoy 経由で期待どおり 200 を返している。
- /subweb2 へ末尾スラッシュ無しでアクセスすると Django の既定の 301 が発生して /subweb2/ にリダイレクトされる。

---

### 何が起きているか
- Envoy のルートは正しく subweb2_service に到達する順序で定義されているため /subweb と競合せずにルーティングされている。
- 301 は Django の CommonMiddleware によるトレーリングスラッシュの自動リダイレクトでありルーティングミスではない。

---

### 検証手順と実行済コマンド
- 確認したコマンドと代表的出力
```bash
kubectl apply -f ../manifests/envoy-gui-config.yaml
kubectl rollout restart deployment/gui-deployment
kubectl rollout status deployment/gui-deployment

MINIKUBE_IP=$(minikube ip)
curl -v -H "Host: test.dev.local" http://${MINIKUBE_IP}/subweb2
# → 301 location: /subweb2/

curl -v -H "Host: test.dev.local" http://${MINIKUBE_IP}/subweb2/
# → 200 Hello from subweb2

curl -v -H "Host: test.dev.local" http://${MINIKUBE_IP}/subweb
# → 200 Hello from Sub Web
```
- Envoy 設定が反映されていることは config_dump で確認済みを前提とする。

---

### 推奨の小改善（差分スニペット）
- 競合を確実に防ぐため subweb2 ルートを先頭に置き、パス境界を正規表現で厳密にマッチさせる。clusters も載せる。

```yaml
# ルート（route_config.virtual_hosts[].routes の先頭に追加）
- match:
    safe_regex:
      regex: "^/subweb2($|/)"
  route:
    cluster: subweb2_service
    idle_timeout: 3600s

# clusters に追加
- name: subweb2_service
  connect_timeout: 0.5s
  type: STRICT_DNS
  lb_policy: ROUND_ROBIN
  dns_lookup_family: V4_ONLY
  load_assignment:
    cluster_name: subweb2_service
    endpoints:
    - lb_endpoints:
      - endpoint:
          address:
            socket_address:
              address: subweb2-service.default.svc.cluster.local.
              port_value: 80
```

- WebSocket を使う予定があれば HttpConnectionManager に `codec_type: HTTP1` と `upgrade_configs: - upgrade_type: websocket` を維持する。

---

### 追加の検証／運用コマンド
- ルート順と cluster 存在を確認する:
```bash
POD=$(kubectl get pod -l app=gui -o jsonpath='{.items[0].metadata.name}')
kubectl port-forward pod/$POD 9901:9901 >/dev/null 2>&1 & echo $! > /tmp/epf.pid
curl -sS http://127.0.0.1:9901/config_dump > /tmp/envoy_config_dump_after.json
kill $(cat /tmp/epf.pid); rm -f /tmp/epf.pid

jq '.configs[] | .bootstrap.static_resources.listeners[]?.filter_chains[]?.filters[]? | select(.name=="envoy.filters.network.http_connection_manager") | .typed_config.route_config.virtual_hosts[] | .routes' /tmp/envoy_config_dump_after.json
jq '.configs[] | .bootstrap.static_resources.clusters[]? | select(.name=="subweb2_service")' /tmp/envoy_config_dump_after.json
```
- 設定を元に戻す（バックアップからのロールバック）:
```bash
kubectl apply -f /tmp/envoy-gui-config.orig.yaml
kubectl rollout restart deployment/gui-deployment
kubectl rollout status deployment/gui-deployment
```

---

### 留意点と運用メモ
- Django が末尾スラッシュでリダイレクトする仕様のため外部クライアントは `/subweb2/` を使うか curl の `-L` でリダイレクト追従を行う。
- 正規表現ルートは順序依存の問題を防ぐ強力な手法であり複雑なパス構成では推奨する。
- WebSocket を有効にするバックエンドは Envoy の upgrade_configs と codec_type の検証を定期的に行う。
