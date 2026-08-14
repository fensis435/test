# frozen_string_literal: true

# ----------------------------------------------------------------------------
# React(Vite dev server, デフォルト http://localhost:5173)からの
# クロスオリジンリクエストを許可する。
#
# 許可オリジンは環境変数化しておき、Cognito移行後も(フロントエンドの
# オリジン自体は変わらない前提のため)このファイルを変更せずに済むように
# しておく。credentials: false としているのは、認証情報をCookieではなく
# Authorizationヘッダ(Bearer)で受け渡す設計のため(Cookie送信を許可する
# 必要がない)。
# ----------------------------------------------------------------------------

Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins ENV.fetch("FRONTEND_ORIGIN", "http://localhost:5173")

    resource "/api/*",
             headers: :any,
             methods: %i[get post options],
             credentials: false
  end
end
