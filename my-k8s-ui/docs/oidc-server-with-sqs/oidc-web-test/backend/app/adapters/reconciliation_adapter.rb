# frozen_string_literal: true

require "net/http"
require "json"
require "time"
require "uri"
require "set"

# ----------------------------------------------------------------------------
# 駆動アダプター(Driving Adapter / Primary Adapter)。
#
# SQS(CloudTrail/EventBridge相当)による通知だけでは、以下のケースで
# ユーザーDBが不完全・不整合になりうるという弱点があった:
#   - イベントの取りこぼし(SQSは標準キューで順序保証がない。
#     AdminCreateUserより先にAdminEnableUserだけを処理してしまう等)
#   - ポーラーの長時間停止によるメッセージ保持期間超過
#   - そもそもSQS経由の通知は「変更された属性の差分」のみで、
#     全属性のスナップショットではない
#
# 本アダプターは、oidc-dev-server(本番ではCognito)の全ユーザー一覧を
# 定期的に取得し、UserSyncApplicationService(コアロジック)へ
# 「現在の状態」をイベントとして再投入することで、上記の欠落を
# 事後的に補正する。イベント駆動の即時性(SQS)と、定期突き合わせの
# 完全性保証(本アダプター)を組み合わせる、一般的なReconciliationパターン。
#
# UserSyncApplicationServiceは無改修。event_time に oidc-dev-server 側の
# updatedAt をそのまま使うことで、「既に最新のユーザーはリコンサイル側が
# 何もしない(:skipped_stale)」という挙動が、コアロジック側の既存の
# 順序保証ガードだけで自然に成立する(本アダプター側で特別扱いする
# コードを書く必要がない)。
# ----------------------------------------------------------------------------

class ReconciliationAdapter
  PAGE_LIMIT = 100

  def initialize(
    use_case: UserSyncApplicationService.new,
    issuer: ENV.fetch("OIDC_ISSUER"),
    admin_email: ENV.fetch("RECONCILE_ADMIN_EMAIL"),
    admin_password: ENV.fetch("RECONCILE_ADMIN_PASSWORD")
  )
    @use_case = use_case
    @issuer = issuer.to_s.chomp("/")
    @admin_email = admin_email
    @admin_password = admin_password
    @admin_token = nil
    @admin_token_expires_at = nil
  end

  # 1回分のリコンサイルを実行する。
  # @return [Hash] { applied:, skipped:, deleted: } の件数サマリー
  def run_once
    run_started_at = Time.now
    remote_user_ids = Set.new
    applied = 0
    skipped = 0

    each_remote_user do |remote_user|
      remote_user_ids << remote_user["id"]

      result = @use_case.sync_user_change(to_upsert_event(remote_user))
      result == :applied ? applied += 1 : skipped += 1
    end

    deleted = reconcile_deletions(remote_user_ids, run_started_at)

    Rails.logger.info(
      "[ReconciliationAdapter] run complete: " \
      "applied=#{applied} skipped=#{skipped} deleted=#{deleted} " \
      "(#{remote_user_ids.size} remote users observed)"
    )

    { applied: applied, skipped: skipped, deleted: deleted }
  end

  private

  # oidc-dev-serverの `GET /api/v1/users` をカーソルページネーションで
  # 全件走査する。
  def each_remote_user
    cursor = nil

    loop do
      page = fetch_users_page(cursor)
      page.fetch("items").each { |remote_user| yield remote_user }

      cursor = page["nextCursor"]
      break if cursor.nil?
    end
  end

  def fetch_users_page(cursor)
    query = { limit: PAGE_LIMIT }
    query[:cursor] = cursor if cursor
    get_json("/api/v1/users?#{URI.encode_www_form(query)}")
  end

  def to_upsert_event(remote_user)
    updated_at = Time.iso8601(remote_user.fetch("updatedAt"))

    UserChangeEvent.new(
      # 決定的なevent_id: 同じユーザーが同じupdatedAtのまま複数回の
      # リコンサイル実行をまたいでも、2回目以降はProcessedEventの
      # 一意制約に引っかかり :skipped_duplicate として早期リターンできる
      # (実際に変更が無いユーザーに対して毎回ステイル判定のロジックまで
      # 到達させずに済む、軽量な最適化)。
      event_id: "reconcile:#{remote_user.fetch('id')}:#{updated_at.to_i}",
      event_name: "AdminUpdateUserAttributes",
      user_id: remote_user.fetch("id"),
      event_time: updated_at,
      attributes: {
        "email" => remote_user["email"],
        "given_name" => remote_user["givenName"],
        "family_name" => remote_user["familyName"],
        "status" => remote_user["status"],
      }.compact
    )
  end

  # oidc-dev-server側の一覧に存在しないのに、こちらのDBには残っている
  # ユーザー(AdminDeleteUserイベントの取りこぼし)を検出し、削除イベントを
  # 同じPort経由で投入する。
  #
  # `updated_at < run_started_at` で絞ることで、このリコンサイル実行の
  # 最中に(SQS経由で)新規作成されたユーザーを誤って削除対象にしてしまう
  # 競合を避けている。
  def reconcile_deletions(remote_user_ids, run_started_at)
    deleted = 0

    SyncedUser
      .where.not(external_user_id: remote_user_ids.to_a)
      .where("updated_at < ?", run_started_at)
      .find_each do |stale_user|
        event = UserChangeEvent.new(
          event_id: "reconcile-delete:#{stale_user.external_user_id}:#{run_started_at.to_i}",
          event_name: "AdminDeleteUser",
          user_id: stale_user.external_user_id,
          event_time: run_started_at,
          attributes: {}
        )

        result = @use_case.sync_user_change(event)
        deleted += 1 if result == :applied
      end

    deleted
  end

  # ------------------------------------------------------------------------
  # oidc-dev-server Management API へのHTTPクライアント。
  # register_client.rb / manage_users.rb と同じ設計方針
  # (標準ライブラリのみ、追加gem不要)。
  # ------------------------------------------------------------------------

  def get_json(path)
    ensure_admin_token!

    response = request(Net::HTTP::Get, path)

    if response.code.to_i == 401
      # 管理者トークンが途中で失効した場合、1回だけ再ログインしてリトライする。
      login!
      response = request(Net::HTTP::Get, path)
    end

    unless response.code.to_i == 200
      raise "GET #{path} failed (#{response.code}): #{response.body}"
    end

    JSON.parse(response.body)
  end

  def request(method_class, path)
    uri = URI.parse("#{@issuer}#{path}")
    req = method_class.new(uri)
    req["Authorization"] = "Bearer #{@admin_token}"
    http_for(uri).request(req)
  end

  def ensure_admin_token!
    login! if @admin_token.nil? || Time.now >= @admin_token_expires_at
  end

  def login!
    uri = URI.parse("#{@issuer}/api/v1/auth/login")
    req = Net::HTTP::Post.new(uri)
    req["Content-Type"] = "application/json"
    req.body = JSON.generate(email: @admin_email, password: @admin_password)

    response = http_for(uri).request(req)
    unless response.code.to_i == 200
      raise "Admin login failed (#{response.code}): #{response.body}"
    end

    body = JSON.parse(response.body)
    @admin_token = body.fetch("accessToken")
    # 30秒のマージンを持たせて、期限ギリギリでのリクエスト送信中の
    # 失効を避ける。
    @admin_token_expires_at = Time.iso8601(body.fetch("expiresAt")) - 30
  end

  def http_for(uri)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    http
  end
end
