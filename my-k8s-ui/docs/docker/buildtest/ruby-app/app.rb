require "sinatra"
require "sinatra/base"
require "sqlite3"
require "json"
require "openssl"
require "socket"

set :bind, "0.0.0.0"
set :port, 4567

DB_PATH = "/tmp/test.db"

def db
  db = SQLite3::Database.new(DB_PATH)
  db.execute <<-SQL
    CREATE TABLE IF NOT EXISTS hits (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      created_at TEXT
    );
  SQL
  db
end

get "/" do
  content_type :json
  {
    message: "Hello from Ruby!",
    ruby_version: RUBY_VERSION,
    platform: RUBY_PLATFORM,
    hostname: Socket.gethostname
  }.to_json
end

get "/health" do
  content_type :json
  { status: "ok" }.to_json
end

# sqlite3 (ネイティブ拡張gem) が正しくビルド・リンクされているかの確認用
get "/db" do
  content_type :json
  conn = db
  conn.execute("INSERT INTO hits (created_at) VALUES (?)", [Time.now.to_s])
  count = conn.get_first_value("SELECT COUNT(*) FROM hits")
  conn.close
  { sqlite3_version: SQLite3::SQLITE_VERSION, hit_count: count }.to_json
end

# OpenSSLが正しくリンクされているかの確認用
get "/crypto" do
  content_type :json
  digest = OpenSSL::Digest::SHA256.hexdigest("hello-world")
  { openssl_version: OpenSSL::VERSION, sha256: digest }.to_json
end
