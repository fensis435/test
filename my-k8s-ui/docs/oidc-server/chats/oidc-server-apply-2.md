
## 1. `proxy: true`の実装反映`env.ts`に`OIDC_TRUST_PROXY`を追加します。`.env.example`とK8s ConfigMapにも反映します。構文チェックを行います。## 2. ローカルHTTPS開発ドキュメントの新規作成

前回の説明を正式なドキュメントとして反映します。## 3. 本番(Cognito/EKS)との差異ドキュメント

`PRODUCTION_PARITY.md`として、これまでのADR的な内容を一箇所に集約します。## Node.js不使用についての回答

3つ目の項目は空欄でしたが、お尋ねの質問として回答します。構文チェックとZIP再生成を行い、その後で回答します。DIRECTORY_TREE.mdに新規ドキュメントを反映し、ZIP化します。---

# 3つ目の質問への回答:「React+Vite+Rails8でNode.jsを一切使っていない」場合の懸念

これは解釈が分かれる質問なので、両方のケースについて回答します。

## ケースA:「ローカル開発機にNode.jsをインストールしていない(Dockerコンテナ内だけで完結させている)」場合

**問題ありません。** `Vite`のCLI自体はNode.js製プログラムなので、Viteを使う以上どこかでNode.jsは実行されますが、それが**開発者のホストマシン上か、Dockerコンテナの中か**は自由です。「ホストにNode.jsをインストールしない」という運用は、むしろ望ましい構成としてよく採用されます。

その場合、`docker-compose.yml`に`frontend`サービスを1つ追加し、Node.jsイメージ内で`npm run dev`を実行するだけです。今回作成した`oidc-dev-server`自体も、既に`Dockerfile`/`docker-compose.yml`でNode.jsをコンテナに閉じ込める構成にしてあるので、同じパターンをReact側にも適用できます。

## ケースB:「Vite自体を使わず、Rails 8のImport Maps(デフォルト)や他のNode不要な仕組みでJSを配信している」場合

これは`これまでの会話の前提(React(Vite)+oidc-client-ts)`と食い違うため、確認させてください。

Rails 8は`importmap-rails`をデフォルトのJSアプローチとして採用しており、npm/webpack/Viteを一切使わずにブラウザのネイティブESModules機能でJSを配信できます。もしこちらを使う想定であれば、

- `oidc-client-ts`はnpmパッケージとして配布されているため、importmapで読み込むには**CDN経由(esm.sh、jsdelivr等)でのURL importに置き換える**必要があります
- ビルドステップ(`vite build`)が存在しないため、`window.crypto.subtle`を使うPKCE生成部分の動作自体は変わりませんが、`.env`ベースの環境変数(`import.meta.env.VITE_*`)という仕組みが使えなくなり、**Rails側で埋め込むか、`<meta>`タグ経由で設定値を渡す**等の代替が必要です

## 共通して重要な点:`oidc-dev-server`自体はNode.js非依存の別プロセス

いずれのケースであっても、**`oidc-dev-server`自体がNode.js(TypeScript)で実装されていることと、React/Railsの開発フローがNode.jsを使うかどうかは、完全に独立した話**です。

`oidc-dev-server`は、ReactやRailsから見れば「HTTPで喋る外部のIdP」でしかありません。ちょうどCognitoがAWS内部で何の言語・ランタイムで実装されているか、利用者側が気にする必要がないのと同じ関係です。React/Rails側が仮に一切Node.jsを使わない構成であっても、`oidc-dev-server`を動かすためだけに、

- ローカル開発機、または開発用Dockerコンテナに1箇所だけNode.js 22系が必要
- CI/CDパイプラインで`oidc-dev-server`をビルド・デプロイする箇所にもNode.jsが必要(ただしこれは他のマイクロサービスと同様、独立したビルドパイプラインとして扱えばよいだけです)

という以上の追加要件は発生しません。K8sマニフェスト(`k8s/deployment.yaml`)も、この`oidc-dev-server`用のPodだけがNode.jsランタイムのコンテナイメージを使い、React/Rails用のPodには一切影響しません。

