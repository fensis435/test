module Pagy
  module BackendOverride
    def pagy(collection, vars = {})
      pagy_instance = Pagy.new(count: collection.count, page: vars[:page] || params[:page], items: vars[:items] || per_page)
      [pagy_instance, collection.offset(pagy_instance.offset).limit(pagy_instance.vars[:items])]
    end
  end
end
