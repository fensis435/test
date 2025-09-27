# 設計詳細: WildcardサブドメインIngress＋Envoyサイドカー＋Flask/Django Sub Web構成

---

## 1. WildcardサブドメインのIngress設定

外部から `*.example.com` でGUIサーバへアクセスを許可するには、Ingressリソースでワイルドカードホストを指定します。  

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: gui-wildcard-ingress
  annotations:
    kubernetes.io/ingress.class: nginx
spec:
  tls:
  - hosts:
    - "*.example.com"
    secretName: wildcard-tls-secret
  rules:
  - host: "*.example.com"
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

- TLSはワイルドカード証明書に対応したSecretを使用  
- CORSやRateLimitはIngressアノテーションで一元管理可能  

---

## 2. Envoyをサイドカーとして配置しリバースプロキシ

GUIやSub Web Pod内にEnvoyコンテナをサイドカーとしてデプロイし、全トラフィックをEnvoy経由で処理します。

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: gui-deployment
spec:
  template:
    spec:
      containers:
      - name: envoy
        image: envoyproxy/envoy:v1.24
        args:
        - --config-path /etc/envoy/envoy.yaml
        volumeMounts:
        - name: envoy-config
          mountPath: /etc/envoy
      - name: gui
        image: your-gui-image
      volumes:
      - name: envoy-config
        configMap:
          name: envoy-gui-config
```

Envoy設定のポイント：  
- `listener` でポート 8080 を受け、`cluster` に GUI と Sub Web を定義  
- ルーティングはリクエストヘッダやパス (`/subweb`) で振り分け  
- JWT の `Authorization` ヘッダは `include_headers` で透過  

---

## 3. JWT認証とセッションテーブル(DB)照会フロー

1. ユーザーはAuthサーバから取得したJWTを`Authorization: Bearer <token>`でGUIへリクエスト  
2. EnvoyがJWTの署名検証（optional）後、ヘッダをGUI/Sub Webへ転送  
3. アプリ側（Flask/Django）はミドルウェアで  
   - 署名検証  
   - セッションDBを照会し、トークン有効性・ブラックリストをチェック  
4. 問題なければリクエスト処理を継続  

---

## 4. URL書き換えに伴うFlask/Django設定

### Flask

```python
from flask import Flask, Blueprint
app = Flask(__name__, static_url_path='/subweb/static')
app.config['APPLICATION_ROOT'] = '/subweb'

bp = Blueprint('subweb', __name__, url_prefix='/subweb')
# Blueprintにルートを定義…
app.register_blueprint(bp)
```

- `static_url_path` と `APPLICATION_ROOT` で生成URLを `/subweb` 前提に  
- 静的ファイル・テンプレートの参照先を自動調整  

### Django

```python
# settings.py
FORCE_SCRIPT_NAME = '/subweb'
STATIC_URL = '/subweb/static/'

# urls.py
urlpatterns = [
    path('subweb/', include('subweb_app.urls'))
]
```

- `FORCE_SCRIPT_NAME` で `reverse()` や `{% url %}` に先頭パスを付与  
- 静的ファイルの `collectstatic` 出力先も合わせる  

---

## 5. Flask/DjangoのマルチDB設定で外部NamespaceのPostgreSQLを利用

### Flask + SQLAlchemy

```python
app.config['SQLALCHEMY_DATABASE_URI'] = 'postgresql://user:pw@app-db:5432/app'
app.config['SQLALCHEMY_BINDS'] = {
    'session_db': 'postgresql://user:pw@session-db.namespace.svc.cluster.local:5432/session'
}
db = SQLAlchemy(app)

class Session(db.Model):
    __bind_key__ = 'session_db'
    __tablename__ = 'sessions'
    id = db.Column(db.Integer, primary_key=True)
    token = db.Column(db.String)
```

### Django 複数DB

```python
# settings.py
DATABASES = {
    'default': {…},
    'session': {
        'ENGINE': 'django.db.backends.postgresql',
        'HOST': 'session-db.namespace.svc.cluster.local',
        'NAME': 'session',
        …  
    }
}
DATABASE_ROUTERS = ['your_project.db_routers.SessionRouter']
```

- セッション用モデルを `app_label='sessions'` にし、Routerで `session` DBを振り分け  

---

## 6. Sub WebのWebSocket多用時のEnvoy/Nginx設定

EnvoyでWebSocketを透過させる場合：  
```yaml
- name: listener_8080
  filter_chains:
  - filters:
    - name: envoy.filters.network.http_connection_manager
      typed_config:
        "@type": type.googleapis.com/envoy.extensions.filters.network.http_connection_manager.v3.HttpConnectionManager
        upgrade_configs:
        - upgrade_type: websocket
        route_config:
          virtual_hosts:
          - name: subweb
            domains: ["*"]
            routes:
            - match: { prefix: "/subweb/ws" }
              route: { cluster: "subweb" }
```

Nginxの例（参考）  
```
proxy_http_version 1.1;
proxy_set_header Upgrade $http_upgrade;
proxy_set_header Connection "upgrade";
```

- WebSocket専用パスを切り、アップグレードヘッダを転送  
- ヘルスチェックやタイムアウト設定で長時間接続を安定化  

---

## 7. 外部公開URLはGUIサーバのみ

- IngressルールはワイルドカードでGUIサービスだけを公開  
- Sub WebはEnvoy経由 or GUIサーバ内部プロキシのみ  
- セキュリティグループ／NetworkPolicyで外部から直接接続不可に  

---

次の検討ポイントとしては、  
- CI/CDでEnvoy設定や`publicPath`周りのテンプレート自動化  
- OIDC IntrospectionやOAuth2 ProxyによるIngress認可ゲートの導入  
- Prometheus＋GrafanaでJWTトークン検証率やWebSocketコネクション数を可視化  
- IstioやLinkerdを使ったmTLS／認証ポリシー集中管理  

などを深掘りすると、さらに運用とセキュリティを強化できます。
