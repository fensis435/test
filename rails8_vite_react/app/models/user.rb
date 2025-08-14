class User < ApplicationRecord
  has_secure_password
  
  validates :name, presence: true
  validates :email, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :password, length: { minimum: 6 }, if: :password_digest_changed?
  
  def generate_jwt
    JWT.encode(
      { 
        user_id: id, 
        exp: 24.hours.from_now.to_i 
      }, 
      Rails.application.credentials.secret_key_base || Rails.application.secrets.secret_key_base
    )
  end
end
