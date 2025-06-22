class JwtDenylist < ApplicationRecord
  include Devise::JWT::RevocationStrategies::Denylist

  self.table_name = "jwt_denylists"

  # Validations
  validates :jti, presence: true, uniqueness: true
  validates :exp, presence: true

  # Class methods
  def self.jwt_revoked?(payload, user)
    exists?(jti: payload["jti"])
  end

  def self.revoke_jwt(payload, user)
    create!(jti: payload["jti"], exp: Time.at(payload["exp"]))
  end

  # Cleanup expired tokens (can be run via cron job)
  def self.cleanup_expired_tokens
    where("exp < ?", Time.current).delete_all
  end
end
