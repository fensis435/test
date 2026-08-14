# リモートLAN(踏み台等)からのアクセス方法

`localhost`ではなく、同じLAN内の別マシン(Windows/Linuxの踏み台サーバー等)
から `oidc-dev-server` / React / Rails 一式にアクセスするための設定。

`LOCAL_HTTPS_SETUP.md` の構成(mkcert + Caddyリバースプロキシ)を前提とする。

## 前提の整理

「ホスト側(サービスを実際に動かしているマシン)」と「クライアント側(踏み台
やそこからアクセスするWindows/Linux端末)」を区別して考える。対応が必要な
項目は4つ:

1. **バインド**: 各サービスが `127.0.0.1` だけでなく、LAN側のNICでも
   listenしているか
2. **DNS解決**: クライアント側から `idp.dev.test` 等の名前がホストの
   LAN上のIPに解決できるか
3. **証明書信頼**: mkcertの自己署名CAを、クライアント側のOS/ブラウザにも
   信頼させているか
4. **ファイアウォール**: ホスト側でLANからのインバウンド接続が許可されているか

## 1. バインドの確認・修正

### oidc-dev-server(対応不要)

`src/server.ts` の `app.listen(env.PORT, ...)` はホスト名を指定していない
ため、Node.jsのデフォルト動作により**全インターフェース(0.0.0.0相当)で
待ち受ける**。追加対応は不要。

### Rails

Railsの開発サーバー(Puma)は `127.0.0.1` のみにバインドしていることが
多い。明示的に `0.0.0.0` を指定する。

```bash
bin/rails server -b 0.0.0.0
```

または `config/puma.rb` に以下を追加(既存の `port` 行の近く):

```ruby
bind "tcp://0.0.0.0:#{ENV.fetch('PORT', 3001)}"
```

### Caddy(対応不要なことが多いが要確認)

Caddyは既定で全インターフェースにバインドするため通常は対応不要。
`Caddyfile` に明示的に `bind 127.0.0.1` のような記述があれば削除する。

## 2. DNS解決

クライアント側(踏み台やそこからの端末)で `idp.dev.test` 等の名前を、
ホストのLAN上のIPアドレス(例: `192.168.1.50`。`127.0.0.1`ではない)に
解決させる必要がある。2つの方法がある。

### 方法A: クライアント側のhostsファイルを individually 編集(手軽・小規模向け)

**Linux踏み台の場合** (`/etc/hosts`):
```
192.168.1.50  idp.dev.test app.dev.test api.dev.test
```

**Windowsの場合** (`C:\Windows\System32\drivers\etc\hosts`、管理者権限で編集):
```
192.168.1.50  idp.dev.test app.dev.test api.dev.test
```

アクセスするクライアントが増えるたびに全端末で編集が必要になる欠点がある。

### 方法B: LAN内DNSサーバー(dnsmasq等)を立てる(複数人・複数端末向け)

ホスト機、または別途LAN内の管理用マシンで `dnsmasq` を動かし、
`*.dev.test` をホストのIPへ名前解決させる。

```
# /etc/dnsmasq.conf (dnsmasqを動かすマシン側)
address=/dev.test/192.168.1.50
```

LAN内の各クライアントのDNSサーバー設定(またはルーターのDHCP配布DNS)を
このdnsmasqのIPに向ければ、以後クライアント側でのhosts編集は不要になる。
チームで複数人がアクセスする場合はこちらを推奨。

## 3. 証明書信頼の配布

`mkcert -install` は**実行したマシンのみ**にCAを信頼させる。踏み台や
Windows/Linuxクライアント側では、mkcertのルートCA証明書を個別に信頼させる
必要がある。

### ① ルートCA証明書を取り出す(ホスト側で実行)

```bash
mkcert -CAROOT
# 例: /home/user/.local/share/mkcert
```

出力されたディレクトリの `rootCA.pem` を、クライアント側に安全な方法
(scp等)でコピーする。

### ② クライアント側で信頼させる

**Linux踏み台の場合(Ubuntu/Debian系)**:
```bash
sudo cp rootCA.pem /usr/local/share/ca-certificates/mkcert-dev-ca.crt
sudo update-ca-certificates
```

Firefoxは独自の証明書ストアを持つため、上記だけでは信頼されない。
Firefoxでも使う場合は `about:config` から手動インポートするか、
`mkcert -install` をそのマシン上でも実行する(mkcertバイナリと
`CAROOT`環境変数を同じ値に揃えれば、同一のCAとして認識される)。

```bash
export CAROOT=/path/to/copied/mkcert/CAROOT
mkcert -install
```

**Windowsクライアントの場合**:

PowerShell(管理者権限)で:
```powershell
Import-Certificate -FilePath "rootCA.pem" -CertStoreLocation Cert:\LocalMachine\Root
```

または `certmgr.msc` を開き、「信頼されたルート証明機関」→「証明書」→
右クリック「すべてのタスク」→「インポート」から `rootCA.pem` を選択してもよい。

## 4. ファイアウォール

ホスト側のファイアウォールで、Caddyがlistenするポート(通常443)への
LANからのインバウンドを許可する。

**Ubuntu (ufw) の場合**:
```bash
sudo ufw allow from 192.168.1.0/24 to any port 443
```

**Windowsホストの場合**(サービスをWindows側で動かす場合):
```powershell
New-NetFirewallRule -DisplayName "Caddy HTTPS (LAN)" -Direction Inbound -LocalPort 443 -Protocol TCP -RemoteAddress 192.168.1.0/24 -Action Allow
```

## 5. 代替案: SSHポートフォワーディング(踏み台がゲートウェイ的な位置づけの場合)

LANが完全にフラットではなく、踏み台(bastion)がゲートウェイ的な位置づけ
(例: 踏み台からしかホストに到達できないネットワーク分離がある)の場合は、
DNS/証明書配布より**SSHのローカルポートフォワーディング**の方がシンプルな
ことが多い。EKSのSSMポートフォワーディング(bastion EC2経由)と同じ発想。

```bash
# 踏み台側(またはそこからアクセスするWindows/Linux端末)で実行
ssh -L 3000:localhost:3000 \
    -L 5173:localhost:5173 \
    -L 3001:localhost:3001 \
    user@<ホストのIPまたはホスト名>
```

この場合、踏み台側から見ると `http://localhost:3000` 等でそのまま
`oidc-dev-server` にアクセスできる。ただしこの方式は**HTTPのまま**になる
(SSHトンネル自体が暗号化されているため、アプリ側のTLSは必須ではなくなる)。
その場合は `LOCAL_HTTPS_SETUP.md` の独自ドメイン化は不要で、
`OIDC_ISSUER=http://localhost:3000` のまま(元のlocalhost運用)に戻せる。

**ただし注意**: PKCEに必要な`crypto.subtle`はブラウザ側の secure context
判定に基づく。SSHフォワーディング先が踏み台自身の `localhost:5173` で
あれば `http://localhost` は secure context として扱われるため問題ないが、
Windows端末のブラウザから**踏み台のIP経由**(`http://<踏み台IP>:5173`)で
アクセスする場合は secure context の対象外になり、PKCE生成が失敗する。
この場合は本ドキュメント前半のHTTPS化(方法1〜4)が必要になる。

## まとめ: どちらを選ぶべきか

| 状況 | 推奨方式 |
|---|---|
| 踏み台からブラウザで `localhost` として振る舞わせられる(踏み台自身のブラウザで操作) | 5. SSHポートフォワーディング(HTTPのまま) |
| Windows端末等、踏み台とは別の端末のブラウザからアクセスしたい | 1〜4. mkcert + Caddy + DNS(HTTPS化必須) |
| チームで複数人・複数端末からアクセスする | 2の方法B(LAN内DNS)を選ぶ |
