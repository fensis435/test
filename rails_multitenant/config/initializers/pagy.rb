require "pagy"
require "pagy/extras/metadata"
require "pagy/extras/overflow"

Pagy::DEFAULT[:items]     = 25
Pagy::DEFAULT[:max_pages] = 200
Pagy::DEFAULT[:overflow]  = :last_page

# Include Pagy::Backend in all API controllers
ActiveSupport.on_load(:action_controller_api) do
  include Pagy::Backend
end
