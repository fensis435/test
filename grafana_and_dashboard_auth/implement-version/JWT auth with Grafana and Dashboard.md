Kubernetes環境でRailsの独自JWT認証を使ってGrafanaとKubernetes Dashboardへのパスワードレス認証を実装する方法を提示します。

## アーキテクチャ概要

1. **Rails認証プロキシ**: JWTを検証してユーザー情報を抽出
2. **Nginx/Traefik**: リバースプロキシとして認証結果をヘッダーで転送
3. **Grafana**: Auth Proxyモードで外部認証を受け入れ
4. **Kubernetes Dashboard**: Tokenベース認証への変換

## 実装手順

### 1. Rails認証プロキシの実装
### 2. Nginx Ingress設定
### 3. Grafana設定
### 4. Grafanaの権限制御スクリプト
### 5. Kubernetes Dashboard用の設定
### 6. Kubernetes Dashboard自動ログイン用のフロントエンド実装
### 7. Railsルーティング設定
### 8. デプロイ手順スクリプト
## 重要なポイントと注意事項

### セキュリティ考慮事項

1. **JWT検証の厳密性**
   - トークンの有効期限チェック
   - DBセッションとの整合性確認
   - HTTPS必須

2. **CORS設定**
   ```ruby
   # config/initializers/cors.rb
   Rails.application.config.middleware.insert_before 0, Rack::Cors do
     allow do
       origins 'grafana.yourdomain.com', 'k8s-dashboard.yourdomain.com'
       resource '/auth/*',
         headers: :any,
         methods: [:get, :post, :options],
         credentials: true
     end
   end
   ```

3. **NetworkPolicy**
   ```yaml
   apiVersion: networking.k8s.io/v1
   kind: NetworkPolicy
   metadata:
     name: auth-proxy-policy
     namespace: default
   spec:
     podSelector:
       matchLabels:
         app: rails-app
     ingress:
     - from:
       - namespaceSelector:
           matchLabels:
             name: ingress-nginx
   ```

### Kubernetes Dashboard の制限事項

Kubernetes Dashboardは完全なパスワードレス認証が難しいため、以下の2つのアプローチがあります:

**アプローチA**: カスタムプロキシページ
- Railsで中間ページを作成
- トークンを自動取得して注入

**アプローチB**: カスタムDashboard実装
- React等で独自のK8s管理UIを作成
- Rails APIを経由してK8s APIを呼び出し

### テスト方法

```bash
# 認証エンドポイントのテスト
curl -v -H "Cookie: jwt_token=YOUR_JWT_TOKEN" \
  https://yourdomain.com/auth/verify

# Grafanaへのアクセステスト（ブラウザで）
# 1. Railsアプリにログイン
# 2. https://grafana.yourdomain.com にアクセス
# 3. 自動的にログインされることを確認
```

この実装により、RailsのJWT認証を使ってGrafanaとKubernetes Dashboardへのシングルサインオンが実現できます。ご質問があればお気軽にどうぞ!