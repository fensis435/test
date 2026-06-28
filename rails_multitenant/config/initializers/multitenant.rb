require_relative "../../lib/tenant_resolver/tenant_context"
require_relative "../../lib/tenant_resolver/resolver"
require_relative "../../lib/database_switcher/connection_manager"
require_relative "../../lib/database_switcher/connection_pool_registry"
require_relative "../../lib/database_switcher/connection_resolver"

# Register tenant isolation middleware
Rails.application.config.middleware.use TenantIsolationMiddleware

# Configure Pagy defaults
require "pagy/extras/metadata"
Pagy::DEFAULT[:items] = 25
Pagy::DEFAULT[:max_pages] = 200
