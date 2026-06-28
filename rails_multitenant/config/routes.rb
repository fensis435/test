Rails.application.routes.draw do
  healthcheck

  namespace :api do
    namespace :v1 do
      # Tenant management (system admin only)
      namespace :admin do
        resources :tenants, only: %i[index show create update destroy] do
          member do
            post :suspend
            post :activate
            post :provision_database
          end
        end
      end

      # Tenant-scoped resources
      resources :users, only: %i[index show create update destroy] do
        collection do
          get :me
        end
      end

      resources :memberships, only: %i[index show create update destroy]

      resources :audit_logs, only: %i[index show]
    end
  end

  # Error handling
  match "/404", to: "api/v1/errors#not_found", via: :all
  match "/422", to: "api/v1/errors#unprocessable", via: :all
  match "/500", to: "api/v1/errors#internal_server_error", via: :all
end
