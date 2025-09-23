# BIND9 インストールと設定手順

---

## 1. BIND9 のインストール

### Ubuntu / Debian 系
```bash
sudo apt update
sudo apt install -y bind9 bind9utils
```

### RHEL / CentOS / AlmaLinux 系
```bash
sudo dnf install -y bind bind-utils
```

---

## 2. 既存のローカル DNS サービス停止確認

### AlmaLinux 9 の場合
不要。ただし以下でポート 53 が占有されていないかをチェックします。
```bash
sudo ss -tupln | grep :53
```

### Ubuntu 24.04 の場合
```bash
sudo systemctl stop systemd-resolved
sudo systemctl disable systemd-resolved
sudo rm /etc/resolv.conf
echo "nameserver 127.0.0.1" | sudo tee /etc/resolv.conf
```
元に戻す場合:
```bash
cd /etc
sudo ln -s ../run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
sudo systemctl start systemd-resolved
sudo systemctl enable systemd-resolved
```

---

## 3. DNS 更新用 TSIG 鍵の生成
```bash
tsig-keygen -a hmac-sha256 external-dns-key > external-dns.key
cat external-dns.key
```
`external-dns.key` の `secret` 行に書かれた Base64 値が TSIG 鍵になります。

---

## 4. IP 範囲の特定

1. ノードの IP 範囲確認  
   ```bash
   ip a
   ```
   - 例: `192.168.0.36/24`

2. Pod のネットワーク範囲取得  
   ```bash
   kubectl get nodes -o json | jq -r '.items[].spec.podCIDR'
   ```
   - 例: `10.244.0.0/24`

3. Service クラスタ IP 範囲取得  
   ```bash
   kubectl cluster-info dump | grep -i service-cluster-ip-range
   ```
   - 例: `--service-cluster-ip-range=10.96.0.0/12`

---

## 5. bind9 オプション設定例

`/etc/bind/named.conf.options` に下記を追加して再帰問い合わせを許可します。

```conf
options {
  directory "/var/cache/bind";
  listen-on port 53 { any; };
  forwarders {
    8.8.8.8;    // 上位 DNS Primary
    8.8.4.4;    // 上位 DNS Secondary
  };
  recursion yes;
  allow-query { any; };
  allow-recursion {
    127.0.0.1;            // localhost
    192.168.49.0/24;      // ノードのネットワーク
    10.244.0.0/16;        // Pod のネットワーク
    10.96.0.0/12;         // Service のネットワーク
  };
  forward first;
  dnssec-validation auto;
  listen-on-v6 { any; };
  querylog yes;
};
```

---

## 6. named.conf.local の設定

```conf
key "external-dns-key" {
  algorithm hmac-sha256;
  secret     "<external-dns.key の secret 値>";
};

zone "dev.local" {
  type master;
  file "/var/cache/bind/dev.local.zone";
  allow-update   { key external-dns-key; };
  allow-transfer { key external-dns-key; };
};
```

---

## 7. ゾーンファイル作成

`/var/cache/bind/dev.local.zone` を以下の内容で用意します。

```dns
$TTL 300
@   IN SOA ns1.dev.local. admin.dev.local. (
      2025010101 ; serial
      3600       ; refresh
      1800       ; retry
      604800     ; expire
      300        ; minimum
)
    IN NS  ns1.dev.local.
ns1 IN A   192.168.49.1
```

ファイル所有者を `bind:bind` に変更:
```bash
sudo chown bind:bind /var/cache/bind/dev.local.zone
```

---

## 8. bind9 の起動・確認

```bash
sudo named-checkconf
sudo systemctl restart bind9
sudo systemctl enable bind9
sudo systemctl status bind9
```

上記でエラーが出なければ、BIND9 サーバが稼働中です。

---

# External-DNS のインストールと設定

---

## 1. Namespace と RBAC の準備

```bash
kubectl create namespace external-dns
```

`rbac.yaml` を用意して以下を適用:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: external-dns
  namespace: external-dns
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: external-dns
rules:
  - apiGroups: [""]
    resources: ["services","endpoints","pods"]
    verbs: ["get","watch","list"]
  - apiGroups: ["extensions","networking.k8s.io"]
    resources: ["ingresses"]
    verbs: ["get","watch","list"]
  - apiGroups: [""]
    resources: ["nodes"]
    verbs: ["list","watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: external-dns-viewer
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: external-dns
subjects:
  - kind: ServiceAccount
    name: external-dns
    namespace: external-dns
```

```bash
kubectl apply -f rbac.yaml
```

---

## 2. TSIG シークレットの作成

```bash
kubectl -n external-dns create secret generic external-dns-secret \
  --from-literal=secret="<external-dns.key の secret 値>"
```

---

## 3. Deployment マニフェスト (install-external-dns.sh)

```bash
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: external-dns
  namespace: external-dns
spec:
  replicas: 1
  selector:
    matchLabels:
      app: external-dns
  template:
    metadata:
      labels:
        app: external-dns
    spec:
      serviceAccountName: external-dns
      securityContext:
        fsGroup: 65534
      containers:
        - name: external-dns
          image: registry.k8s.io/external-dns/external-dns:v0.19.0
          args:
            - --source=service
            - --source=ingress
            - --provider=rfc2136
            - --rfc2136-host=192.168.49.1       # BIND9 サーバの IP
            - --rfc2136-port=53
            - --rfc2136-zone=dev.local          # ローカルドメイン
            - --rfc2136-tsig-keyname=external-dns-key
            - --rfc2136-tsig-secret=<external-dns.key の secret 値> # 本来は環境変数から読み込むはずだがうまくいかないので直接指定
            - --rfc2136-tsig-secret-alg=hmac-sha256
            - --txt-owner-id=external-dns
            - --registry=txt
            - --policy=sync
            - --interval=30s
            - --log-level=debug
          env:
            - name: RFC2136_TSIG_SECRET
              valueFrom:
                secretKeyRef:
                  name: external-dns-secret
                  key: secret
EOF
```

---

## 4. 動作確認

1. Deployment の再起動  
   ```bash
   kubectl -n external-dns rollout restart deployment external-dns
   ```

2. ログに「Update succeeded」が出ているか  
   ```bash
   kubectl -n external-dns logs deployment/external-dns --tail=50 \
     | grep -E "Adding RR|Update succeeded|error"
   ```

3. DNS レコードの取得  
   ```bash
   dig @192.168.0.36 app-mt7r21xq.dev.local A +short
   ```

4. 更新テスト（動作しない場合）  
   ```bash
   nsupdate -y hmac-sha256:external-dns-key:<secret> <<EOF
   server 192.168.0.36 53
   zone dev.local
   update add manual.dev.local 300 A 1.2.3.4
   send
   EOF
   dig @192.168.0.36 manual.dev.local A +short
   ```
 
# Ingress+NGINXによる動作確認

## 1. 自動化パイプライン

### 1.1 Helm チャート構成

```
my-app-chart/
├── Chart.yaml
├── values.yaml
└── templates/
    ├── deployment.yaml
    ├── service.yaml
    └── ingress.yaml
```

#### Chart.yaml

```yaml
apiVersion: v2
name: my-app
version: 0.1.0
```

#### values.yaml

```yaml
image:
  repository: nginx
  tag: stable

service:
  port: 80

ingress:
  host: ""
```

#### templates/deployment.yaml

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "my-app.fullname" . }}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: {{ include "my-app.fullname" . }}
  template:
    metadata:
      labels:
        app: {{ include "my-app.fullname" . }}
    spec:
      containers:
        - name: app
          image: {{ .Values.image.repository }}:{{ .Values.image.tag }}
          ports:
            - containerPort: {{ .Values.service.port }}
```

#### templates/service.yaml

```yaml
apiVersion: v1
kind: Service
metadata:
  name: {{ include "my-app.fullname" . }}
spec:
  type: LoadBalancer
  selector:
    app: {{ include "my-app.fullname" . }}
  ports:
    - port: {{ .Values.service.port }}
      targetPort: {{ .Values.service.port }}
```

#### templates/ingress.yaml

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: {{ include "my-app.fullname" . }}-ingress
  annotations:
    external-dns.alpha.kubernetes.io/hostname: {{ .Values.ingress.host }}.
spec:
  ingressClassName: nginx
  rules:
    - host: {{ .Values.ingress.host }}
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: {{ include "my-app.fullname" . }}
                port:
                  number: {{ .Values.service.port }}
```

---

### 1.2 ユーザー登録＆デプロイスクリプト (`register-app.sh`)

```bash
#!/usr/bin/env bash
set -eo pipefail

# 1) 8桁ランダムハッシュ生成
HASH=$(head -c 100 /dev/urandom | tr -dc 'a-z0-9' | head -c 8)

# 2) リリース名＆Namespace
RELEASE="app-${HASH}"

# 3) サブドメイン組み立て
DOMAIN="${RELEASE}.dev.local"

# 4) Helm インストール（Namespace 自動作成＆ホスト値を渡す）
helm install "$RELEASE" ./my-app-chart \
  --namespace "$RELEASE" --create-namespace \
  --set ingress.host="$DOMAIN"

echo "▶ リリース: $RELEASE"
echo "▶ Namespace: $RELEASE"
echo "▶ URL: http://$DOMAIN"
```

---

## 手動 vs 自動の境界

| 項目                           | 手動（初回１回）                             | 自動化                                 |
|--------------------------------|---------------------------------------------|----------------------------------------|
| K8s + MetalLB + Ingress   | k8sにhelmでinstall        | –                                      |
| MetalLB IPプール設定           | `kubectl apply -f metallb-pool.yaml`         | –                                      |
| ホストBind9 起動            | install+config作成 + 起動                         | –                                      |
| ExternalDNS インストール設定   | Helm でチャートを一度導入                     | –                                      |
| ユーザー登録時のドメイン生成   | –                                           | `register-app.sh` 実行                 |
| Helm インストール（Namespace） | –                                           | 同上                                   |
| Ingress → DNS レコード登録     | –                                           | ExternalDNS が自動対応            |
| LoadBalancer IP 割当           | –                                           | MetalLB が自動                           |

---

このフローで「8桁ハッシュ付きサブドメインを自動生成 → 自動 Helm install → ExternalDNS による自動 DNS レコード登録 → MetalLB による外部IP払い出し → サービス公開」までが実現できます。  

 # `helm create` デフォルトテンプレート向けの values.yaml 例

`helm create my-app` で生成されるテンプレート（`deployment.yaml`／`service.yaml`／`ingress.yaml`）なら、以下のような `values.yaml` を用意して、あとは `--set` でサブドメインを流し込むだけで動作します。

---

## 1. values.yaml のサンプル

```yaml
# ---------------------------
# 基本設定
# ---------------------------
replicaCount: 1

image:
  repository: nginx
  pullPolicy: IfNotPresent
  tag: stable

# ---------------------------
# Service 設定
# ---------------------------
service:
  type: LoadBalancer
  port: 80
  targetPort: 80

# ---------------------------
# Ingress 設定
# ---------------------------
ingress:
  enabled: true
  ingressClassName: nginx
  annotations:
    external-dns.alpha.kubernetes.io/hostname: ""  # ここを--setで上書き
  hosts:
    - host: ""   # ここを--setで上書き
      paths:
        - path: /
          pathType: Prefix

# ---------------------------
# オプション（必要に応じて）
# ---------------------------
autoscaling:
  enabled: false

resources: {}
nodeSelector: {}
tolerations: []
affinity: {}
```

---

## 2. Helm インストール／アップグレード時のコマンド例

```bash
HASH=$(head /dev/urandom | tr -dc 'a-z0-9' | head -c 8)
RELEASE="app-${HASH}"
DOMAIN="${RELEASE}.dev.local"

helm upgrade --install "$RELEASE" ./my-app-chart \
  --namespace "$RELEASE" --create-namespace \
  --values values.yaml \
  --set ingress.annotations."external-dns\.alpha-kubernetes\.io/hostname"="$DOMAIN" \
  --set ingress.hosts[0].host="$DOMAIN"
```

ポイント：

- `ingress.annotations.external-dns.alpha-kubernetes.io/hostname` はドメイン名そのものを指定  
- `ingress.hosts[0].host` も同じドメインを指定  
- `upgrade --install` を使えば「既存ならアップグレード、なければインストール」になる  

---

## 3. 動作確認の流れ

1. Helm でデプロイ後、MetalLB が Service に外部 IP を払い出す  
2. ExternalDNS が Ingress のアノテーションを拾い、CoreDNS に A レコードを追加  
3. `dig $DOMAIN @<CoreDNSのIP>` で名前解決を確認  
4. `curl http://$DOMAIN` でアプリにアクセス  

---
