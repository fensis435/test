#!/usr/bin/env ruby
# frozen_string_literal: true

require "net/http"
require "json"
require "uri"
require "optparse"

# ----------------------------------------------------------------------------
# oidc-dev-server の Management API (/api/v1/users, /api/v1/users/:id/groups)
# を操作する簡易CLI。
#
# scripts/register_client.rb と同じ設計方針: 標準ライブラリのみで完結させ、
# 追加gemのインストールを不要にする。
#
# 使い方:
#   ruby scripts/manage_users.rb <command> [options]
#
# コマンド一覧:
#   list                                 ユーザー一覧
#   show <user_id>                       ユーザー詳細
#   create                               ユーザー作成
#   update <user_id>                     ユーザー更新(氏名/メールアドレス)
#   delete <user_id>                     ユーザー削除(論理削除)
#   enable <user_id>                     有効化
#   disable <user_id>                    無効化
#   set-password <user_id>               パスワード強制変更
#   add-group <user_id> <group_id>       グループ追加
#   remove-group <user_id> <group_id>    グループ削除
#
# 共通オプション(環境変数でも指定可。CLIオプションが優先):
#   --issuer URL            既定: 環境変数 OIDC_ISSUER、無ければ http://localhost:3000
#   --admin-email EMAIL     既定: 環境変数 ADMIN_EMAIL
#   --admin-password PASS   既定: 環境変数 ADMIN_PASSWORD
#   --json                  レスポンスをそのままJSONで出力する(既定は簡易テーブル表示)
#
# 例:
#   export OIDC_ISSUER=https://idp.dev.test
#   export ADMIN_EMAIL=admin@example.com
#   export ADMIN_PASSWORD=change-me-please
#
#   ruby scripts/manage_users.rb list
#   ruby scripts/manage_users.rb list --status ACTIVE --all
#   ruby scripts/manage_users.rb create --email new@example.com --password correct-horse-battery
#   ruby scripts/manage_users.rb show <user_id>
#   ruby scripts/manage_users.rb disable <user_id>
#   ruby scripts/manage_users.rb delete <user_id>
# ----------------------------------------------------------------------------

COMMANDS = %w[list show create update delete enable disable set-password add-group remove-group].freeze

def usage_and_exit(message = nil)
  warn "Error: #{message}\n\n" if message
  warn <<~USAGE
    Usage: ruby scripts/manage_users.rb <command> [options] [args]

    Commands:
      list                                 ユーザー一覧
      show <user_id>                       ユーザー詳細
      create                                ユーザー作成
      update <user_id>                     ユーザー更新(氏名/メールアドレス)
      delete <user_id>                     ユーザー削除(論理削除)
      enable <user_id>                     有効化
      disable <user_id>                    無効化
      set-password <user_id>               パスワード強制変更
      add-group <user_id> <group_id>       グループ追加
      remove-group <user_id> <group_id>    グループ削除

    Common options:
      --issuer URL
      --admin-email EMAIL
      --admin-password PASSWORD
      --json                (整形テーブルではなく生JSONで出力)

    list専用:
      --email STRING         メールアドレスの部分一致検索
      --status ACTIVE|DISABLED
      --group-id-filter ID   所属グループで絞り込み
      --limit N              1ページの件数(既定20)
      --cursor CURSOR        前回のnextCursor
      --all                  全ページを自動取得して結合表示

    create専用:
      --email EMAIL          必須
      --password PASSWORD    必須(temporaryPassword、8文字以上)
      --given-name NAME
      --family-name NAME
      --group-id ID          所属させるグループID(複数指定可)

    update専用:
      --email EMAIL
      --given-name NAME
      --family-name NAME

    set-password専用:
      --password PASSWORD    必須

    環境変数 OIDC_ISSUER / ADMIN_EMAIL / ADMIN_PASSWORD でも指定可能
    (CLIオプションが指定されればそちらが優先される)。
  USAGE
  exit 1
end

command = ARGV.shift
usage_and_exit("command is required") if command.nil?
usage_and_exit("unknown command '#{command}'") unless COMMANDS.include?(command)

options = {
  issuer: ENV.fetch("OIDC_ISSUER", "http://localhost:3000"),
  admin_email: ENV["ADMIN_EMAIL"],
  admin_password: ENV["ADMIN_PASSWORD"],
  json: false,
  limit: 20,
  group_ids: []
}

parser = OptionParser.new do |opts|
  opts.on("--issuer URL") { |v| options[:issuer] = v }
  opts.on("--admin-email EMAIL") { |v| options[:admin_email] = v }
  opts.on("--admin-password PASSWORD") { |v| options[:admin_password] = v }
  opts.on("--json") { options[:json] = true }

  opts.on("--email EMAIL") { |v| options[:email] = v }
  opts.on("--status STATUS") { |v| options[:status] = v }
  opts.on("--group-id-filter ID") { |v| options[:group_id_filter] = v }
  opts.on("--limit N", Integer) { |v| options[:limit] = v }
  opts.on("--cursor CURSOR") { |v| options[:cursor] = v }
  opts.on("--all") { options[:all] = true }

  opts.on("--password PASSWORD") { |v| options[:password] = v }
  opts.on("--given-name NAME") { |v| options[:given_name] = v }
  opts.on("--family-name NAME") { |v| options[:family_name] = v }
  opts.on("--group-id ID") { |v| options[:group_ids] << v }
end

begin
  parser.parse!(ARGV)
rescue OptionParser::ParseError => e
  usage_and_exit(e.message)
end

usage_and_exit("--admin-email is required (or set ADMIN_EMAIL)") unless options[:admin_email]
usage_and_exit("--admin-password is required (or set ADMIN_PASSWORD)") unless options[:admin_password]

# ------------------------------------------------------------------------------
# HTTPヘルパー
# ------------------------------------------------------------------------------

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

def login(issuer, email, password)
  response, body = request_json(
    Net::HTTP::Post,
    "#{issuer}/api/v1/auth/login",
    body: { email: email, password: password }
  )
  unless response.code.to_i == 200
    warn "管理者ログインに失敗しました (#{response.code}): #{body}"
    exit 1
  end
  body.fetch("accessToken")
end

def api(method, issuer, path, access_token, body: nil)
  response, parsed = request_json(
    method,
    "#{issuer}#{path}",
    body: body,
    headers: { "Authorization" => "Bearer #{access_token}" }
  )
  [response, parsed]
end

def abort_on_error(response, parsed)
  return if response.code.to_i.between?(200, 299)

  warn "APIエラー (#{response.code}): #{JSON.pretty_generate(parsed)}"
  exit 1
end

# ------------------------------------------------------------------------------
# 表示ヘルパー
# ------------------------------------------------------------------------------

def print_json(obj)
  puts JSON.pretty_generate(obj)
end

def print_users_table(users)
  if users.empty?
    puts "(該当するユーザーはいません)"
    return
  end

  rows = users.map do |u|
    [u["id"], u["email"], u["status"], u["emailVerified"] ? "true" : "false", u["createdAt"]]
  end
  headers = %w[id email status emailVerified createdAt]
  widths = headers.each_index.map { |i| ([headers[i].length] + rows.map { |r| r[i].to_s.length }).max }

  print_row = lambda do |cols|
    puts cols.each_with_index.map { |c, i| c.to_s.ljust(widths[i]) }.join("  ")
  end

  print_row.call(headers)
  print_row.call(widths.map { |w| "-" * w })
  rows.each { |r| print_row.call(r) }
end

# ------------------------------------------------------------------------------
# コマンド実装
# ------------------------------------------------------------------------------

access_token = login(options[:issuer], options[:admin_email], options[:admin_password])

case command
when "list"
  all_items = []
  cursor = options[:cursor]

  loop do
    query = { limit: options[:limit] }
    query[:email] = options[:email] if options[:email]
    query[:status] = options[:status] if options[:status]
    query[:groupId] = options[:group_id_filter] if options[:group_id_filter]
    query[:cursor] = cursor if cursor

    path = "/api/v1/users?#{URI.encode_www_form(query)}"
    response, body = api(Net::HTTP::Get, options[:issuer], path, access_token)
    abort_on_error(response, body)

    all_items.concat(body["items"])
    cursor = body["nextCursor"]

    break unless options[:all] && cursor
  end

  if options[:json]
    print_json({ "items" => all_items, "nextCursor" => cursor })
  else
    print_users_table(all_items)
    puts "\n次ページのcursor: #{cursor}" if cursor && !options[:all]
  end

when "show"
  user_id = ARGV.shift or usage_and_exit("show requires <user_id>")
  response, body = api(Net::HTTP::Get, options[:issuer], "/api/v1/users/#{user_id}", access_token)
  abort_on_error(response, body)
  print_json(body)

when "create"
  usage_and_exit("--email is required") unless options[:email]
  usage_and_exit("--password is required") unless options[:password]

  payload = {
    email: options[:email],
    temporaryPassword: options[:password]
  }
  payload[:givenName] = options[:given_name] if options[:given_name]
  payload[:familyName] = options[:family_name] if options[:family_name]
  payload[:groupIds] = options[:group_ids] unless options[:group_ids].empty?

  response, body = api(Net::HTTP::Post, options[:issuer], "/api/v1/users", access_token, body: payload)
  abort_on_error(response, body)
  puts "作成しました:"
  print_json(body)

when "update"
  user_id = ARGV.shift or usage_and_exit("update requires <user_id>")

  payload = {}
  payload[:email] = options[:email] if options[:email]
  payload[:givenName] = options[:given_name] if options[:given_name]
  payload[:familyName] = options[:family_name] if options[:family_name]
  usage_and_exit("update: at least one of --email/--given-name/--family-name is required") if payload.empty?

  response, body = api(Net::HTTP::Patch, options[:issuer], "/api/v1/users/#{user_id}", access_token, body: payload)
  abort_on_error(response, body)
  puts "更新しました:"
  print_json(body)

when "delete"
  user_id = ARGV.shift or usage_and_exit("delete requires <user_id>")
  response, body = api(Net::HTTP::Delete, options[:issuer], "/api/v1/users/#{user_id}", access_token)
  abort_on_error(response, body)
  puts "削除しました(論理削除): #{user_id}"

when "enable"
  user_id = ARGV.shift or usage_and_exit("enable requires <user_id>")
  response, body = api(Net::HTTP::Post, options[:issuer], "/api/v1/users/#{user_id}/enable", access_token)
  abort_on_error(response, body)
  print_json(body)

when "disable"
  user_id = ARGV.shift or usage_and_exit("disable requires <user_id>")
  response, body = api(Net::HTTP::Post, options[:issuer], "/api/v1/users/#{user_id}/disable", access_token)
  abort_on_error(response, body)
  print_json(body)

when "set-password"
  user_id = ARGV.shift or usage_and_exit("set-password requires <user_id>")
  usage_and_exit("--password is required") unless options[:password]

  response, body = api(
    Net::HTTP::Put,
    options[:issuer],
    "/api/v1/users/#{user_id}/password",
    access_token,
    body: { newPassword: options[:password] }
  )
  abort_on_error(response, body)
  puts "パスワードを変更しました: #{user_id}"

when "add-group"
  user_id = ARGV.shift or usage_and_exit("add-group requires <user_id> <group_id>")
  group_id = ARGV.shift or usage_and_exit("add-group requires <user_id> <group_id>")
  response, body = api(
    Net::HTTP::Post,
    options[:issuer],
    "/api/v1/users/#{user_id}/groups/#{group_id}",
    access_token
  )
  abort_on_error(response, body)
  puts "グループに追加しました: user=#{user_id} group=#{group_id}"

when "remove-group"
  user_id = ARGV.shift or usage_and_exit("remove-group requires <user_id> <group_id>")
  group_id = ARGV.shift or usage_and_exit("remove-group requires <user_id> <group_id>")
  response, body = api(
    Net::HTTP::Delete,
    options[:issuer],
    "/api/v1/users/#{user_id}/groups/#{group_id}",
    access_token
  )
  abort_on_error(response, body)
  puts "グループから削除しました: user=#{user_id} group=#{group_id}"
end
