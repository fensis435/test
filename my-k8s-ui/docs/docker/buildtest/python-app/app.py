import platform
import socket
import sqlite3
import ssl
import hashlib
from flask import Flask, jsonify

app = Flask(__name__)

DB_PATH = "/tmp/test_py.db"


def get_db():
    conn = sqlite3.connect(DB_PATH)
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS hits (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            created_at TEXT
        )
        """
    )
    return conn


@app.route("/")
def index():
    return jsonify(
        message="Hello from Python!",
        python_version=platform.python_version(),
        platform=platform.platform(),
        hostname=socket.gethostname(),
    )


@app.route("/health")
def health():
    return jsonify(status="ok")


# sqlite3 標準モジュールが正しくリンクされているかの確認用
@app.route("/db")
def db():
    conn = get_db()
    conn.execute("INSERT INTO hits (created_at) VALUES (datetime('now'))")
    conn.commit()
    count = conn.execute("SELECT COUNT(*) FROM hits").fetchone()[0]
    conn.close()
    return jsonify(sqlite3_version=sqlite3.sqlite_version, hit_count=count)


# ssl(OpenSSL)標準モジュールが正しくリンクされているかの確認用
@app.route("/crypto")
def crypto():
    digest = hashlib.sha256(b"hello-world").hexdigest()
    return jsonify(openssl_version=ssl.OPENSSL_VERSION, sha256=digest)


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
