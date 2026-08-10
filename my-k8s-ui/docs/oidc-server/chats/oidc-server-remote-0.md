## open-web-test/frontendの.envを編集
```bash
oidc-web-test/frontend$ cat .env
VITE_OIDC_ISSUER=https://idp.dev.test
VITE_OIDC_CLIENT_ID=react-web-test-client
VITE_OIDC_REDIRECT_URI=https://app.dev.test/callback
VITE_OIDC_POST_LOGOUT_REDIRECT_URI=https://app.dev.test/
VITE_OIDC_SCOPES=openid email profile groups offline_access

# Rails v8 APIのベースURL
VITE_RAILS_API_BASE_URL=https://api.dev.test
```

## open-web-test/frontendのvite.config.tsを編集
```bash
vaio@ubuntu2404:~/oidc-server/oidc-web-test/frontend$ cat vite.config.ts
import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

// ----------------------------------------------------------------------------
// appType のデフォルト("spa")により、/callback など存在しないパスへの
// 直接アクセスでも index.html が返却される。react-router等のライブラリを
// 追加導入せずに、Authorization Code Flowのredirect_uri先を素のパスとして
// 扱える(トップページのみという要件を満たすための最小構成)。
// ----------------------------------------------------------------------------

export default defineConfig({
  plugins: [react()],
  server: {
    host: true,
    port: 5173,
  },
  allowedHosts: true,
});

```

## open-web-test/backendの.envを編集
```bash
~/oidc-server/oidc-web-test/backend$ cat .env
OIDC_ISSUER=https://idp.dev.test
FRONTEND_ORIGIN=https://app.dev.test
PORT=3001
RAILS_ENV=development
```

## open-web-test/backendの起動方法を修正
```bash
./bin/rails server -b 0.0.0.0 -p 3001
```

## open-dev-serverの.envを編集
```bash
~/oidc-server/oidc-dev-server/backend$ cat .env
===省略===
# --- OIDC Core ---
# Discovery documentのissuerとして公開される値。
# Cognito移行時はここをCognito User Pool issuer URLに切り替えるだけでよい設計。
OIDC_ISSUER=https://idp.dev.test

> # リバースプロキシ(Caddy/nginx/ALB等)配下で動作させる場合は "true" にする。
> # localhostへの直接httpアクセスで開発している場合は "false"(既定値)のままでよ い。
> # 本番(EKS + ALB Ingress)では必ず "true" にすること
> # (Cookie の Secure 属性や protocol 判定が正しく機能しなくなるため)。
OIDC_TRUST_PROXY=true
===省略===
```

## open-dev-serverのvitest.config.tsを編集
```bash
~/oidc-server/oidc-dev-server$ cat vitest.config.ts
import { defineConfig } from "vitest/config";

export default defineConfig({
  server: {
    host: true,
  },
  test: {
    environment: "node",
    include: ["src/**/*.test.ts"],
    coverage: {
      provider: "v8",
      reporter: ["text", "html"],
    },
  },
});

```
