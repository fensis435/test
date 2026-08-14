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
        allowedHosts: true,
    },
});
