### cert-manager を使った SSH 認証の仕組み

cert-manager は通常、SSL/TLS 証明書を発行しますが、その「秘密鍵（PrivateKey）」と「公開鍵（PublicKey）」のペアを SSH 用として流用します。

#### 手順のイメージ

1. **CA の作成:** cert-manager で自己署名の CA（認証局）を作成します。
2. **証明書（鍵ペア）の発行:** `Certificate` リソースを作成し、SSH 鍵として使える `Secret` を生成します。
3. **Pod へのマウント:**
* **送信元 Pod (Ansible実行側):** `Secret` から「秘密鍵」を `~/.ssh/id_rsa` としてマウント。
* **送信先 Pod (rsync受け側):** `Secret` から「公開鍵」を `~/.ssh/authorized_keys` としてマウント。



---

### 実装のポイント（YAML の構成例）

#### 1. cert-manager で鍵ペアを作る

`keyAlgorithm: RSA` を指定して、SSH が理解できる形式で鍵を作らせます。

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: ssh-key-pair
spec:
  secretName: ssh-key-secret # この名前の Secret に鍵が保存される
  commonName: "ssh-auth"
  isCA: false
  usages:
    - digital signature
    - key encipherment
  privateKey:
    algorithm: RSA
    encoding: PKCS1 # SSHが読みやすい形式
    size: 4096
  issuerRef:
    name: my-selfsigned-issuer
    kind: Issuer

```

#### 2. 送信元・送信先の Pod で Secret を共有する

作成された `ssh-key-secret` には、`tls.key`（秘密鍵）と `tls.crt`（公開鍵を含む証明書）が入っています。

* **送信先 (Receiver) の設定例:**
`authorized_keys` ファイルとして公開鍵を配置します。
```yaml
volumeMounts:
- name: ssh-key
  mountPath: /root/.ssh/authorized_keys
  subPath: tls.crt # 公開鍵部分を流用

```


* **送信元 (Sender) の設定例:**
秘密鍵を配置します。
```yaml
volumeMounts:
- name: ssh-key
  mountPath: /root/.ssh/id_rsa
  subPath: tls.key

```



---

### 注意点と限界

1. **ファイルのパーミッション:** Kubernetes の Secret マウント（`defaultMode`）を使って、`~/.ssh` は `0700`、鍵ファイルは `0600` になるよう設定しないと、SSH 実行時に「権限が緩すぎる」と怒られて失敗します。
2. **SSH デーモンの起動:**
Pod 間で SSH を行うには、**送信先の Pod で `sshd` が動いている必要**があります。通常のアプリケーション Pod には `sshd` は入っていないため、サイドカーとして入れるか、自作イメージに含める必要があります。
3. **ホストキーの確認:**
初回接続時に「Are you sure you want to continue connecting?」というプロンプトが出ると Ansible が止まります。Ansible 側で `ansible_ssh_extra_args: "-o StrictHostKeyChecking=no"` を設定して回避するのが一般的です。

### 結論

cert-manager を使えば、**「鍵の生成と有効期限管理（更新）」を自動化**した状態で、Pod 間のパスワードレス SSH/rsync が実現できます。
