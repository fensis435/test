### Kubernetes: subweb Deployment と Service
```yaml
# subweb-deployment-service.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: subweb-deployment
  labels:
    app: subweb
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
          name: http
        readinessProbe:
          httpGet:
            path: /health
            port: 80
          initialDelaySeconds: 2
          periodSeconds: 5
        livenessProbe:
          httpGet:
            path: /health
            port: 80
          initialDelaySeconds: 10
          periodSeconds: 20

---
apiVersion: v1
kind: Service
metadata:
  name: subweb-service
  labels:
    app: subweb
spec:
  type: ClusterIP
  ports:
  - name: http
    port: 80
    targetPort: 80
  selector:
    app: subweb
```

### Envoy 用 ConfigMap（envoy-gui-config ? envoy.yaml を含む）
```yaml
# envoy-configmap.yaml
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
          socket_address:
            address: 0.0.0.0
            port_value: 8080
        filter_chains:
        - filters:
          - name: envoy.filters.network.http_connection_manager
            typed_config:
              "@type": type.googleapis.com/envoy.extensions.filters.network.http_connection_manager.v3.HttpConnectionManager
              stat_prefix: ingress_http
              codec_type: HTTP1
              upgrade_configs:
              - upgrade_type: websocket
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
        dns_lookup_family: V4_ONLY
        load_assignment:
          cluster_name: subweb_service
          endpoints:
          - lb_endpoints:
            - endpoint:
                address:
                  socket_address:
                    address: subweb-service.default.svc.cluster.local.
                    port_value: 80

    admin:
      access_log_path: "/tmp/admin_access.log"
      address:
        socket_address: { address: 127.0.0.1, port_value: 9901 }
```

### GUI Deployment（Envoy + GUI アプリ）と NodePort Service（外部到達用）
```yaml
# gui-deployment-service.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: gui-deployment
  labels:
    app: gui
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
        args: ["envoy", "-c", "/etc/envoy/envoy.yaml", "--service-node", "gui", "--service-cluster", "gui"]
        ports:
        - containerPort: 8080
          name: envoy-http
        volumeMounts:
        - name: envoy-config
          mountPath: /etc/envoy
          readOnly: true
      - name: gui-app
        image: gui-app:latest
        ports:
        - containerPort: 8000
          name: gui-http
      volumes:
      - name: envoy-config
        configMap:
          name: envoy-gui-config
          items:
          - key: envoy.yaml
            path: envoy.yaml

---
apiVersion: v1
kind: Service
metadata:
  name: gui-nodeport
  labels:
    app: gui
spec:
  type: NodePort
  ports:
  - name: http
    port: 80
    targetPort: 8080
    nodePort: 30080
  selector:
    app: gui
```

### 適用手順（イメージビルドと manifest の適用）
1. subweb イメージを minikube 内でビルドして Deployment に反映する:
```bash
eval $(minikube docker-env)
docker build -t subweb-flask:latest ./subweb
# あるいは registry を使う場合は tag/push して Deployment を更新する
```
2. マニフェストを適用:
```bash
kubectl apply -f subweb-deployment-service.yaml
kubectl apply -f envoy-configmap.yaml
kubectl apply -f gui-deployment-service.yaml
```
3. Envoy GUI を外部からテスト（bind9 で *.dev.local を minikube IP に向けている前提）:
```bash
export MINIKUBE_IP=$(minikube ip)
# ブラウザや curl で確認
curl -v -H "Host: test.dev.local" http://${MINIKUBE_IP}/
curl -v -H "Host: foo.test.dev.local" http://${MINIKUBE_IP}/subweb
```

### 重要な運用メモ（必ず確認）
- **DNS**: bind9 のワイルドカードが minikube IP を返すことを dig で必ず確認する。  
- **Envoy の cluster DNS**: FQDN を使う場合は末尾ドットを付けるか ClusterIP を直接埋めることで search/ndots の影響を回避する（上の ConfigMap は末尾ドット付の FQDN を使用）。  
- **WebSocket の安定化**: HttpConnectionManager の codec_type を HTTP1 に固定済み（Envoy が HTTP/2 経由で Upgrade を扱うことによる問題を防ぐ）。  
- **外部公開**: NodePort を使う例を示した。プロダクションでは LoadBalancer / Ingress Controller を推奨。  

必要ならこの YAML をあなたの現行 manifest に合わせて差分化（patch）します。どれを直接適用するか指示してください。
