### caddy install
```bash
sudo apt install -y debian-keyring debian-archive-keyring apt-transport-https curl
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-stable.list
sudo apt update
sudo apt install caddy
```

### Issue a trusted certificate with mkcert
```bash
sudo apt install -y libnss3-tools
mkcert -install # Register the local CA in the OS/browser trust store (run once)
mkcert idp.dev.test app.dev.test api.dev.test
# → Generates idp.dev.test+2.pem and idp.dev.test+2-key.pem
```

### edit setting file
```bash
sudo vi /etc/caddy/Caddyfile
```
modifiy the settintg file as follow.
```text
idp.dev.test {
  tls /etc/caddy/certs/idp.dev.test+2.pem /etc/caddy/certs/idp.dev.test+2-key.pem
  reverse_proxy localhost:3000
}
app.dev.test {
  tls /etc/caddy/certs/idp.dev.test+2.pem /etc/caddy/certs/idp.dev.test+2-key.pem
  reverse_proxy localhost:5173
}
api.dev.test {
  tls /etc/caddy/certs/idp.dev.test+2.pem /etc/caddy/certs/idp.dev.test+2-key.pem
  reverse_proxy localhost:3001
}
```

### restart caddy
```bash
sudo systemctl restart caddy.service
sudo systemctl status caddy.service
```

### Manually editing the client-side hosts file (simple/small-scale approach)

**For a Linux jump host** (`/etc/hosts`):
```
192.168.1.50  idp.dev.test app.dev.test api.dev.test
```

**For Windows** (`C:\Windows\System32\drivers\etc\hosts`; edit with administrator privileges):
```
192.168.1.50  idp.dev.test app.dev.test api.dev.test
```

If you are using dnsmasq on the bastion server, you can register the aforementioned local DNS in its configuration.

### extract the root CA certificate(executed on the host side)
```bash
mkcert -CAROOT
output ex: /home/user/.local/share/mkcert
openssl x509 -in ~/.local/share/mkcert/rootCA.pem -text -noout # Confirm contents
```
Copy the `rootCA.pem` file from the output directory to the client using a secure method (such as scp).

### Case of Windows client
```powershell
Import-Certificate -FilePath "rootCA.pem" -CertStoreLocation Cert:\LocalMachine\Root
```
Alternatively, you can open `certmgr.msc`, navigate to 「信頼されたルート証明機関」→「証明書」→
右クリック「すべてのタスク」→「インポート」 and then select `rootCA.pem`.
