# 結論

サブWebサーバ側でも最低限 JWT の署名検証は必須です。  
さらに「外部公開」や「他サービスから直接呼ばれる」ユースケースでは、セッションDB照会によるトークン有効性チェックも行うべきです。

---

## 認証責任の切り分け

1. GUIサーバが「認証済みかどうか」を担保  
2. サブWebは「そのリクエストが本物の認証済みユーザーか」を再検証  

この二重チェックにより、防御層（Defence in Depth）を強化します。

---

## 内部プロキシ方式の場合

- GUIサーバ経由でのみサブWebが呼ばれる  
- サブWebでは  
  - JWT の署名検証  
  - 必要に応じてペイロード内のユーザー情報チェック  
- セッションDB照会は省略しても可（GUIサーバですでに確認済みの前提）

メリット  
- レイテンシ／DB 負荷の最適化  
- 実装がシンプル

注意点  
- GUIサーバ側の改竄や設定ミスで、不正アクセスを見逃すリスク

---

## 独立公開方式の場合

- サブWebが直接外部や他マイクロサービスからアクセスを受ける  
- サブWebでは  
  - JWT 署名検証  
  - セッションDB照会でトークンの有効性・ブラックリストチェック  
- Flask／Django の JWT 拡張（flask-jwt-extended、SimpleJWT など）で実装

メリット  
- どの経路から来ても一貫した認証チェック  
- セキュリティ要件が高い API や WebSocket エンドポイントに有効

注意点  
- DB への往復コスト／可用性設計が必要  
- 各サービスに接続設定を散らさないよう管理を徹底

---

## 実装イメージ

### Flask（flask-jwt-extended）

```python
from flask_jwt_extended import JWTManager, verify_jwt_in_request, get_jwt
from flask import Flask

app = Flask(__name__)
app.config['JWT_SECRET_KEY'] = 'your-secret'
jwt = JWTManager(app)

@app.before_request
def check_jwt():
    verify_jwt_in_request()           # 署名検証
    claims = get_jwt()
    # 必要ならセッションDBを照会してトークン有効性を確認
```

### Django（SimpleJWT＋カスタム認証）

```python
# settings.py
REST_FRAMEWORK = {
  'DEFAULT_AUTHENTICATION_CLASSES': [
    'rest_framework_simplejwt.authentication.JWTAuthentication',
    'yourapp.auth.SessionAuthentication'  # DB照会を組み込んだ独自クラス
  ],
}

# yourapp/auth.py
from rest_framework_simplejwt.authentication import JWTAuthentication

class SessionAuthentication(JWTAuthentication):
    def authenticate(self, request):
        validated_token = self.get_validated_token(request.headers['Authorization'].split()[1])
        # セッションDB照会によるトークン有効性チェックをここで実装
        return self.get_user(validated_token), validated_token
```
