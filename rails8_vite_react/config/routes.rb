Rails.application.routes.draw do
  # API routes only
  namespace :api do
    namespace :v1 do
      # ユーザー管理
      #resources :users, only: [:create, :show, :update, :destroy] do
      resources :users do
        member do
          put :change_password
          get :sessions
        end
        collection do
          get :me
          get :search
        end
      end
      
      # 認証専用
      post   '/auth/login',      to: 'auth#login'
      post   '/auth/refresh',    to: 'auth#refresh'
      post   '/auth/logout',     to: 'auth#logout'
      get    '/auth/me',         to: 'auth#me'
      delete '/auth/logout_all', to: 'auth#logout_all'
      get    '/auth/sessions',   to: 'auth#sessions'

      # その他のAPIリソース
      #resources :posts do
      #  member do
      #    post :like
      #    delete :like
      #  end
      #  resources :comments, except: [:new, :edit]
      #end

      #resources :categories, only: [:index, :show, :create, :update, :destroy]
      #resources :tags, only: [:index, :show, :create, :destroy]
      #resources :uploads, only: [:create, :show, :destroy]
      #resources :notifications, only: [:index, :show, :update]

      ## 検索機能
      #get '/search', to: 'search#index'
      #get '/search/users', to: 'search#users'
      #get '/search/posts', to: 'search#posts'
    end
  end
  
  # Health check for monitoring
  get '/health', to: 'health#check'
  
  # React SPA用 - すべてのHTMLリクエストをReactに委譲
  root 'frontend#index'
  get '*path', to: 'frontend#index', constraints: ->(req) { 
    !req.xhr? && req.format.html? && !req.path.start_with?('/api')
  }
end
