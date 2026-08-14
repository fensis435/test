require_relative "boot"

# ----------------------------------------------------------------------------
# [設計方針の更新: 2回目]
# 当初 `require "rails/all"` ではなく必要なrailtieのみを明示的にrequireし、
# ActiveRecordを含む多くのコンポーネントを意図的に除外していた
# (「Access Tokenを検証してJSONを返すこと」以外の責務を持たない設計)。
#
# 新要件(Cognitoユーザー情報とバックエンドのユーザーDBを同期する)により、
# このアプリ自体が「仮のユーザーDB」を持つことになったため、
# ActiveRecordのみ追加で有効化する。ActionMailer/ActiveStorage/
# ActionCable等、依然として使わないものは引き続き含めない
# (「本当に必要なものだけを持つ」という原則は維持する)。
# ----------------------------------------------------------------------------
require "rails"
require "action_controller/railtie"
require "active_record/railtie"

# dotenv-rails(Gemfile参照)がBundler.require経由で.envを自動読込する。
# [教訓] 別プロジェクト(oidc-dev-server)で.envの読込漏れによる起動失敗が
# あったため、ここでも明示的にコメントで残しておく。
Bundler.require(*Rails.groups)

module RailsTokenVerifier
  class Application < Rails::Application
    config.load_defaults 8.0

    # API専用モード(セッションCookie/ビュー/アセットパイプライン等を持たない)
    config.api_only = true

    # app/services, app/ports, app/adapters, app/value_objects 配下等を
    # オートロード対象に含める(Rails 8のZeitwerkは app/* 配下を自動で
    # オートロードパスに追加するため、追加設定は基本的に不要だが、
    # 名前空間なしのディレクトリ構成であることを明示するために記載)。
    config.autoload_lib(ignore: %w[assets tasks])

    # このアプリ固有の設定名前空間(config.x.*)。
    # OIDC issuerはCognito移行時にENV変数を切り替えるだけで良い設計とする
    # (config/initializers/oidc.rb 参照)。
    config.x.oidc = ActiveSupport::OrderedOptions.new
  end
end
