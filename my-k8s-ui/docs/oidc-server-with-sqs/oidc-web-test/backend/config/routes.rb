Rails.application.routes.draw do
  namespace :api do
    namespace :v1 do
      resource :whoami, only: [:show], controller: "whoami"

      # [デモ] REST Adapterの動作確認用。前述のコメント(users_controller.rb)
      # の通り、実際のオンプレ本番実装ではこれと同等のエンドポイントが
      # 既に存在する想定。
      namespace :admin do
        resources :users, only: %i[create update destroy]
      end
    end
  end

  get "up" => "rails/health#show", as: :rails_health_check
end
