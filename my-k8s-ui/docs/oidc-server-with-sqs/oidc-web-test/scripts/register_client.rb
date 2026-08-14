#!/usr/bin/env ruby
# frozen_string_literal: true

require "net/http"
require "json"
require "uri"
require "optparse"

# ----------------------------------------------------------------------------
# oidc-dev-server の Management API を使い、React(Vite)フロントエンド用の
# Public Client(client_secretなし、PKCE必須)を登録するワンショットスクリプト。
#
# 使い方:
#   ruby scripts/register_client.rb \
#     --issuer http://localhost:3000 \
#     --admin-email admin@example.com \
#     --admin-password change-me-please
#
# 事前準備: oidc-dev-server 側で管理者アカウントが作成済みであること
#   (例: SEED_ADMIN_PASSWORD=xxx npx prisma db seed)
#
# [修正の経緯]
#   1. `--post-logout-redirect-uri` を指定するCLIオプションが存在せず、
#      `postLogoutRedirectUris` が常に既定値(http://localhost:5173/)の
#      ままハードコードされていた。`--redirect-uri` を独自ドメインに
#      変更しても、postLogoutRedirectUrisだけ食い違ったままになり、
#      別途手動でPATCHする必要があった。
#   2. Clientが既に登録済み(409)の場合、何も更新せず単にスキップしていた。
#      localhost↔独自ドメイン間の切替のように、同じclient_idのまま
#      redirectUris等を更新したいケースが実際には多いため、
#      `--update` フラグで既存Clientの更新(PATCH)にも対応させた。
# ----------------------------------------------------------------------------

options = {
  issuer: ENV.fetch("OIDC_ISSUER", "http://localhost:3000"),
  client_id: "react-web-test-client",
  redirect_uri: "http://localhost:5173/callback",
  post_logout_redirect_uri: "http://localhost:5173/",
  update: false
}

OptionParser.new do |opts|
  opts.banner = "Usage: ruby scripts/register_client.rb [options]"
  opts.on("--issuer URL") { |v| options[:issuer] = v }
  opts.on("--admin-email EMAIL") { |v| options[:admin_email] = v }
  opts.on("--admin-password PASSWORD") { |v| options[:admin_password] = v }
  opts.on("--client-id ID") { |v| options[:client_id] = v }
  opts.on("--redirect-uri URI") { |v| options[:redirect_uri] = v }
  opts.on("--post-logout-redirect-uri URI") { |v| options[:post_logout_redirect_uri] = v }
  opts.on("--update", "Clientが既に存在する場合、redirectUris等をPATCHで更新する") { options[:update] = true }
end.parse!

abort "エラー: --admin-email は必須です" unless options[:admin_email]
abort "エラー: --admin-password は必須です" unless options[:admin_password]

def request_json(method, url, body: nil, headers: {})
  uri = URI.parse(url)
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = uri.scheme == "https"

  request = method.new(uri)
  request["Content-Type"] = "application/json"
  headers.each { |k, v| request[k] = v }
  request.body = JSON.generate(body) if body

  response = http.request(request)
  parsed = response.body.to_s.empty? ? {} : JSON.parse(response.body)
  [response, parsed]
end

def print_summary(issuer, client_id, redirect_uri)
  puts ""
  puts "frontend/.env の以下を確認してください(通常はデフォルト値のままでよい):"
  puts ""
  puts "VITE_OIDC_ISSUER=#{issuer}"
  puts "VITE_OIDC_CLIENT_ID=#{client_id}"
  puts "VITE_OIDC_REDIRECT_URI=#{redirect_uri}"
end

puts "管理者ログイン中... (#{options[:issuer]}/api/v1/auth/login)"

login_response, login_body = request_json(
  Net::HTTP::Post,
  "#{options[:issuer]}/api/v1/auth/login",
  body: { email: options[:admin_email], password: options[:admin_password] }
)

abort "管理者ログインに失敗しました (#{login_response.code}): #{login_body}" unless login_response.code.to_i == 200

access_token = login_body.fetch("accessToken")
puts "管理者ログイン成功。"

client_payload = {
  clientId: options[:client_id],
  isPublic: true,
  tokenEndpointAuthMethod: "NONE",
  redirectUris: [options[:redirect_uri]],
  postLogoutRedirectUris: [options[:post_logout_redirect_uri]],
  allowedScopes: %w[openid email profile offline_access groups],
  grantTypes: %w[authorization_code refresh_token]
}

puts "Client '#{options[:client_id]}' (Public Client) を登録中..."

client_response, client_body = request_json(
  Net::HTTP::Post,
  "#{options[:issuer]}/api/v1/clients",
  body: client_payload,
  headers: { "Authorization" => "Bearer #{access_token}" }
)

case client_response.code.to_i
when 201
  puts ""
  puts "登録成功。"
  print_summary(options[:issuer], client_body.fetch("clientId"), options[:redirect_uri])
when 409
  puts "Client '#{options[:client_id]}' は既に登録済みです。"

  unless options[:update]
    puts "redirectUris/postLogoutRedirectUrisを最新の値に更新したい場合は --update を付けて再実行してください。"
    exit 0
  end

  puts "--update が指定されたため、redirectUris/postLogoutRedirectUrisを更新します..."

  update_response, update_body = request_json(
    Net::HTTP::Patch,
    "#{options[:issuer]}/api/v1/clients/#{options[:client_id]}",
    body: {
      redirectUris: [options[:redirect_uri]],
      postLogoutRedirectUris: [options[:post_logout_redirect_uri]]
    },
    headers: { "Authorization" => "Bearer #{access_token}" }
  )

  if update_response.code.to_i == 200
    puts ""
    puts "更新成功。"
    print_summary(options[:issuer], update_body.fetch("clientId"), options[:redirect_uri])
  else
    abort "Client更新に失敗しました (#{update_response.code}): #{update_body}"
  end
else
  abort "Client登録に失敗しました (#{client_response.code}): #{client_body}"
end
