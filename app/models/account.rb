class Account < ApplicationRecord
  # Relationships
  belongs_to :user
  has_many :transactions, dependent: :destroy

  # Encrypt sensitive Plaid data
  attr_encrypted :plaid_access_token, key: ENV["ENCRYPTION_KEY"]

  # Validations
  validates :name, :account_type, :institution_name, presence: true
  validates :plaid_account_id, presence: true, uniqueness: true
  validates :account_type, inclusion: { in: %w[checking savings credit_card investment loan] }
  validates :currency, presence: true, inclusion: { in: %w[USD EUR GBP CAD] }

  # Scopes
  scope :active, -> { where(active: true) }
  scope :by_type, ->(type) { where(account_type: type) }

  # Instance methods
  def display_name
    "#{institution_name} - #{name}"
  end

  def balance_display
    if account_type == "credit_card"
      -balance_current # Show credit card balances as positive when you owe money
    else
      balance_current
    end
  end

  def needs_sync?
    last_sync_at.nil? || last_sync_at < 1.hour.ago
  end

  def formatted_balance
    "$%.2f" % balance_display
  end
end
