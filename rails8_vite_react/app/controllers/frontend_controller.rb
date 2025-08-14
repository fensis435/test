class FrontendController < ActionController::Base
  def index
    render file: Rails.root.join('public', 'vite', 'index.html'), layout: false
  end
end
