class UrlApiPermission < ApplicationRecord
  belongs_to :permission

  validates :url_pattern, presence: true
  validates :http_method, presence: true, inclusion: { in: %w[GET POST PUT PATCH DELETE] }
  validates :url_pattern, uniqueness: { scope: [:http_method, :permission_id] }

  scope :for_url, ->(pattern, method) {
    where(url_pattern: pattern, http_method: method)
  }
end
