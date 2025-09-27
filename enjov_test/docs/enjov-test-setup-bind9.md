### 目的とゴール
local の bind9 を使ってワイルドカードサブドメインを minikube 環境に向け、Envoy をリバースプロキシとして機能させる流れと確認手順を一式で示す。手順は bind9 のゾーン作成から Envoy 設定、Kubernetes 内のサービス確認、WebSocket を含む動作確認とトラブルシュートまでをカバーする。

---

### 前提と準備
- minikube と kubectl が動作している。  
- root 権限で bind9 をインストールできる。  
- Envoy は Kubernetes 上の Pod（ここでは gui デプロイ内の envoy コンテナ）で稼働している。  
- サービス名: subweb-service、namespace: default を想定する。必要なら適宜名前を置き換える。  

インストール例（Debian/Ubuntu）:
```bash
sudo apt update
sudo apt install -y bind9 bind9utils
```

---

### 1 bind9 によるワイルドカードサブドメイン設定
1. ゾーン定義ファイルを作る。ここではゾーン名を dev.local、minikube の IP を使う例を示す。minikube の IP を取得する:
```bash
MINIKUBE_IP=$(minikube ip)
echo $MINIKUBE_IP
```
2. named.conf.local にゾーンを追加:
```bash
sudo tee -a /etc/bind/named.conf.local > /dev/null <<'EOF'
zone "dev.local" {
  type master;
  file "/etc/bind/db.dev.local";
};
EOF
```
3. ゾーンファイル /etc/bind/db.dev.local を作成:
```bash
sudo tee /etc/bind/db.dev.local > /dev/null <<EOF
$TTL    600
@       IN      SOA     ns.dev.local. admin.dev.local. (
                          2025092701 ; Serial
                          3600       ; Refresh
                          1800       ; Retry
                          604800     ; Expire
                          600 )      ; Negative Cache TTL
;
@       IN      NS      ns.dev.local.
ns      IN      A       127.0.0.1
@       IN      A       ${MINIKUBE_IP}
*       IN      A       ${MINIKUBE_IP}
EOF
```
4. bind9 を再起動して設定反映:
```bash
sudo systemctl restart bind9
sudo systemctl status bind9 --no-pager
```
5. ローカルホストの DNS を bind9 に向ける。Ubuntu の場合 /etc/resolv.conf を直接編集せず NetworkManager の設定で 127.0.0.1 を優先 DNS に設定するか、テストは dig で直接 bind9 に問い合わせる:
```bash
dig @127.0.0.1 test.dev.local +short
dig @127.0.0.1 anything.dev.local +short
# 期待: MINIKUBE_IP が返る
```

---

### 2 Kubernetes / Envoy 側設定（要点）
1. Kubernetes 側に subweb Deployment と Service が存在していることを確認:
```bash
kubectl get deploy,svc -l app=subweb -o wide
kubectl get endpoints subweb-service -o wide
kubectl get pods -l app=subweb -o wide
```
2. Envoy 設定（ConfigMap）での重要ポイント:
- route に Host や path を使って `/subweb` と `/subweb/socket.io` を subweb にルーティングすること。  
- WebSocket を扱うため HttpConnectionManager に `upgrade_configs` に websocket を含めること。  
- DNS に依存する場合 cluster の type を STRICT_DNS にするか、ClusterIP を直接指定すること。  
- DNS search/ndots の影響を避けるため cluster の socket_address に FQDN の末尾にドットを付けるか clusterIP を使うこと。

Envoy の clusters と listeners のサンプル抜粋（ConfigMap data.envoy.yaml 内）:
```yaml
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
          route_config:
            name: local_route
            virtual_hosts:
            - name: backend
              domains: ["*"]
              routes:
              - match: { prefix: "/subweb/socket.io" }
                route:
                  cluster: subweb_service
                  idle_timeout: 3600s
              - match: { prefix: "/subweb" }
                route:
                  cluster: subweb_service
                  idle_timeout: 3600s
              - match: { prefix: "/" }
                route: { cluster: gui_service }
          http_filters:
          - name: envoy.filters.http.router
            typed_config:
              "@type": type.googleapis.com/envoy.extensions.filters.http.router.v3.Router
          upgrade_configs:
          - upgrade_type: websocket

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
                address: subweb-service.default.svc.cluster.local.
                port_value: 80
```
3. ConfigMap を適用して Envoy デプロイを再起動:
```bash
kubectl apply -f envoy-gui-config.yaml
kubectl rollout restart deployment/gui-deployment
kubectl rollout status deployment/gui-deployment
```

---

### 3 検証手順（順序立てて実行）
1. DNS が期待どおり動くか確認:
```bash
dig @127.0.0.1 test.dev.local +short
dig @127.0.0.1 sub.test.dev.local +short
# 期待: MINIKUBE_IP が返る
```
2. ブラウザやホストから Host ヘッダでアクセス:
```bash
export IP=$(minikube ip)
curl -v -H "Host: test.dev.local" http://${IP}/
curl -v -H "Host: foo.test.dev.local" http://${IP}/subweb
# 期待: GUI と /subweb が正しいコンテンツを返す
```
3. サービス名でクラスタ内 DNS が解決されるか確認:
```bash
kubectl run --rm -i --tty dns-test --image=busybox --restart=Never -- \
  sh -c "nslookup subweb-service.default.svc.cluster.local; echo ---; nslookup subweb-service.default.svc.cluster.local."
```
4. Pod から直接サービスにアクセスして差異を確認:
```bash
SUB_IP=$(kubectl get pod -l app=subweb -o jsonpath='{.items[0].status.podIP}')
CLUSTER_IP=$(kubectl get svc subweb-service -o jsonpath='{.spec.clusterIP}')
kubectl run --rm -i --tty http-test --image=curlimages/curl:8.4.0 --restart=Never -- \
  sh -c "echo svc-name; curl -sv http://subweb-service.default.svc.cluster.local/subweb || true; \
         echo; echo cluster-ip; curl -sv http://${CLUSTER_IP}/subweb || true; \
         echo; echo pod-ip; curl -sv http://${SUB_IP}:80/subweb || true"
# 期待: svc-name と cluster-ip と pod-ip が同じ応答を返す
```
5. Envoy の管理 API で設定とクラスターを確認:
```bash
POD=$(kubectl get pod -l app=gui -o jsonpath='{.items[0].metadata.name}')
kubectl port-forward pod/$POD 9901:9901 >/dev/null 2>&1 & echo $! > /tmp/epf.pid
curl -sS http://127.0.0.1:9901/clusters | sed -n '1,200p'
curl -sS http://127.0.0.1:9901/listeners | sed -n '1,200p'
curl -sS http://127.0.0.1:9901/config_dump > /tmp/envoy_config_dump.json
kill $(cat /tmp/epf.pid) || true; rm -f /tmp/epf.pid
jq '.configs[] | .bootstrap.static_resources.listeners[]?.filter_chains[]?.filters[]? | select(.name=="envoy.filters.network.http_connection_manager") | .typed_config' /tmp/envoy_config_dump.json
# 期待: /subweb と /subweb/socket.io の route があり upgrade_configs に websocket が存在する
```
6. Socket.IO の polling と WebSocket を検証:
```bash
# Polling 接続
curl -i "http://test.dev.local/subweb/socket.io/?EIO=4&transport=polling"

# WebSocket 接続は socket.io-client を使う
# ローカルで node ws-test.js を実行
node ws-test.js
# 期待: connect と sid がログに出る。subweb 側ログに Upgrade 成功が出る
kubectl logs -l app=subweb --tail=200
```

---

### 4 トラブルシュートとよくある対処
- DNS が意図しない IP を返す場合: bind9 のゾーンファイルと serial を確認して bind9 を再起動する。クライアントの DNS キャッシュをクリアして dig で直接確認する。  
- FQDN 解決で search ドメインに引っかかる場合: Envoy の cluster 定義で FQDN の末尾にドットを付けるか Pod の dnsConfig で ndots を調整する。  
```yaml
spec:
  template:
    spec:
      dnsConfig:
        options:
        - name: ndots
          value: "2"
```
- Envoy が HTTP/2 経由で接続して WebSocket のフレーム処理が壊れる場合: HttpConnectionManager の `codec_type` を `HTTP1` に変更して再起動する。  
```bash
kubectl get configmap envoy-gui-config -o yaml > /tmp/envoy-cm.yaml
sed -i 's/codec_type: AUTO/codec_type: HTTP1/g' /tmp/envoy-cm.yaml
kubectl apply -f /tmp/envoy-cm.yaml
kubectl rollout restart deployment/gui-deployment
```
- wscat で「Invalid WebSocket frame」等が出る場合: socket.io は Engine.IO 独自の最初のフレーミングを行うため生の wscat は信頼できる検証手段ではない。socket.io-client を検証基準として使う。  
- Envoy がサービス名で意図しないホストに接続する場合: 一時的に ConfigMap に clusterIP を直接埋めて動作確認する。  
```bash
CLUSTER_IP=$(kubectl get svc subweb-service -o jsonpath='{.spec.clusterIP}')
kubectl get configmap envoy-gui-config -o yaml > /tmp/envoy-cm.yaml
sed -i "s/subweb-service.default.svc.cluster.local./${CLUSTER_IP}/g" /tmp/envoy-cm.yaml
kubectl apply -f /tmp/envoy-cm.yaml
kubectl rollout restart deployment/gui-deployment
```

---

### 5 ログと確認ポイントのまとめ
- bind9: `dig @127.0.0.1 foo.dev.local +short` が minikube IP を返すこと。  
- Kubernetes: `kubectl get svc subweb-service`, `kubectl get endpoints subweb-service` が正しいこと。  
- Envoy: `config_dump` において `route_config` で `/subweb` と `/subweb/socket.io` が `subweb_service` に向いており `upgrade_configs` に websocket があること。  
- subweb: `kubectl logs -l app=subweb` に `Upgrade to websocket successful` と `Sending packet` のログが残ること。  
- クライアント: `node ws-test.js` が `connected <sid>` を返すこと。

---

### 最後に
上の手順を実行して得られた主要な出力を貼れば、具体的な設定差分や問題箇所に対するパッチを作成して提供する。必要であればあなたの現行 envoy-gui-config.yaml を受け取り差分を作成する。
