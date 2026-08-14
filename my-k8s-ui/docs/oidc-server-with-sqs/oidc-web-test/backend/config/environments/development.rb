Rails.application.configure do
  config.enable_reloading = true
  config.eager_load = false
  config.consider_all_requests_local = true
  config.server_timing = true

  config.log_level = :debug
  config.log_tags = [:request_id]

  config.action_controller.raise_on_missing_callback_actions = true

  # ----------------------------------------------------------------------------
  # [開発専用の割り切り] Rails 7以降のデフォルトのHost Authorizationは
  # localhostからのアクセスを通常許可するが、動作環境差異で弾かれるのを
  # 避けるため、開発検証専用アプリとして明示的にhostsチェックを無効化する。
  # 本番運用を想定するアプリではこれを行わないこと。
  # ----------------------------------------------------------------------------
  config.hosts.clear
end
