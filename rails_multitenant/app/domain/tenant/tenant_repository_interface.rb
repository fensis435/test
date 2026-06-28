module Domain
  module Tenant
    module TenantRepositoryInterface
      # @param id [String] UUID
      # @return [Domain::Tenant::Tenant, nil]
      def find_by_id(id)
        raise NotImplementedError, "#{self.class}#find_by_id must be implemented"
      end

      # @param slug [String]
      # @return [Domain::Tenant::Tenant, nil]
      def find_by_slug(slug)
        raise NotImplementedError, "#{self.class}#find_by_slug must be implemented"
      end

      # @param page [Integer]
      # @param per_page [Integer]
      # @param filters [Hash]
      # @return [Array<Domain::Tenant::Tenant>]
      def find_all(page: 1, per_page: 25, filters: {})
        raise NotImplementedError, "#{self.class}#find_all must be implemented"
      end

      # @param tenant [Domain::Tenant::Tenant]
      # @return [Domain::Tenant::Tenant]
      def save(tenant)
        raise NotImplementedError, "#{self.class}#save must be implemented"
      end

      # @param tenant [Domain::Tenant::Tenant]
      # @return [Boolean]
      def delete(tenant)
        raise NotImplementedError, "#{self.class}#delete must be implemented"
      end

      # @param slug [String]
      # @return [Boolean]
      def exists_by_slug?(slug)
        raise NotImplementedError, "#{self.class}#exists_by_slug? must be implemented"
      end

      # @param status [String]
      # @return [Integer]
      def count_by_status(status)
        raise NotImplementedError, "#{self.class}#count_by_status must be implemented"
      end
    end
  end
end
