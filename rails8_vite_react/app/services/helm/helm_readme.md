Rails 8.0のアプリケーション向けに、Helmを操作するサービスクラスを作成します。Rails 8.0向けのHelm操作ライブラリを作成しました。以下の特徴を持つサービスクラスです：

## 主な機能

### 1. リポジトリ操作
- パブリック・プライベートリポジトリの追加
- リポジトリの更新・一覧表示・削除
- 認証情報の設定（username/password）

### 2. リリース管理
- チャートのインストール・アップグレード・アンインストール
- ロールバック機能
- values設定（直接指定とファイル指定）
- バージョン指定

### 3. 情報取得
- リリース一覧・ステータス・履歴の取得
- マニフェストとvaluesの取得
- チャート検索

### 4. 開発支援機能
- テンプレート生成
- ドライラン実行
- プラグイン管理

## エラーハンドリング
- カスタム例外クラスでエラーを分類
- チャート/リリース未発見エラー
- コマンド実行エラー

## 使用方法

```ruby
# 基本的な使用例
helm = HelmService.new(namespace: 'production', timeout: 600)

# リポジトリ追加（パブリック）
helm.add_repository('bitnami', 'https://charts.bitnami.com/bitnami')

# リポジトリ追加（プライベート）
helm.add_repository('private-repo', 'https://private.example.com/charts',
                   username: ENV['HELM_USER'], password: ENV['HELM_PASSWORD'])

# アプリケーションデプロイ
helm.install('my-app', 'bitnami/nginx', 
             values: { 'replicaCount' => 3, 'image.tag' => 'latest' })

# ステータス確認
status = helm.get_release_status('my-app')
```

このライブラリはRailsのビジネスロジック内で安全にHelmを操作でき、適切なログ出力とエラーハンドリングを提供します。テストも含めているので、継続的な品質保証も可能です。