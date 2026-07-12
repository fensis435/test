# テスト用アプリの使い方

## ディレクトリ構成

```
testapp/
├── ruby-app/
│   ├── Gemfile        # sinatra + puma(C拡張) + sqlite3(ネイティブ拡張)
│   ├── app.rb
│   └── config.ru
├── python-app/
│   ├── requirements.txt  # flask + gunicorn
│   └── app.py
├── Dockerfile.ruby-app    # build/deps/runtime の3段構成
└── Dockerfile.python-app  # build/deps/runtime の3段構成
```

Gemfile.lock はあえて含めていません。`Dockerfile.ruby-app` の deps ステージで
`bundle lock && bundle install` を実行し、その場でロックファイルを生成します。
(初回ビルド時にネットワークアクセスで rubygems.org から解決します)

## ビルド

このディレクトリ(testapp/)をビルドコンテキストにして実行してください。

```bash
cd testapp

# Rubyアプリ
docker buildx build --provenance=false -f Dockerfile.ruby-app -t ruby-testapp .

# Pythonアプリ
docker buildx build --provenance=false -f Dockerfile.python-app -t python-testapp .
```

## 起動

```bash
docker run --rm -p 4567:4567 ruby-testapp
```

別ターミナルで:
```bash
curl http://localhost:4567/
curl http://localhost:4567/health
curl http://localhost:4567/db      # sqlite3ネイティブ拡張の動作確認
curl http://localhost:4567/crypto  # OpenSSLリンクの動作確認
```

Pythonアプリも同様に:
```bash
docker run --rm -p 5000:5000 python-testapp
```

```bash
curl http://localhost:5000/
curl http://localhost:5000/health
curl http://localhost:5000/db
curl http://localhost:5000/crypto
```

## 確認ポイント

- `/db` エンドポイントが200を返せば、ネイティブ拡張(gem: sqlite3、標準モジュール: sqlite3)が
  runtimeイメージ上でも正しくロードできている証拠です。
- `/crypto` エンドポイントが200を返せば、OpenSSLの共有ライブラリが正しくリンクされている証拠です。
- どちらもエラーになる場合は `docker logs <container_id>` でスタックトレースを確認し、
  `cannot open shared object file` 系のエラーが出ていれば runtime ステージの
  `microdnf install` にライブラリが足りていない可能性があります。
