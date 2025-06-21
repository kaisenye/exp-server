class Transaction < ApplicationRecord
  # Relationships
  belongs_to :account
  has_one :user, through: :account
  has_many :transaction_classifications, foreign_key: "transaction_id", dependent: :destroy
  has_many :categories, through: :transaction_classifications

  # Validations
  validates :plaid_transaction_id, presence: true, uniqueness: true
  validates :amount, :currency, :date, presence: true
  validates :description, presence: true

  # Scopes
  scope :recent, -> { order(date: :desc) }
  scope :by_date_range, ->(start_date, end_date) { where(date: start_date..end_date) }
  scope :expenses, -> { where("amount < 0") }
  scope :income, -> { where("amount > 0") }
  scope :pending, -> { where(pending: true) }
  scope :settled, -> { where(pending: false) }

  # Instance methods
  def amount_display
    amount.abs
  end

  def formatted_amount
    "$%.2f" % amount_display
  end

  def is_expense?
    amount < 0
  end

  def is_income?
    amount > 0
  end

  def primary_category
    transaction_classifications.order(confidence_score: :desc).first&.category
  end

  def auto_classify!
    # Simple rule-based classification for now
    # In a real app, you'd use ML or more sophisticated rules
    category_name = case merchant_name&.downcase
    when /grocery|supermarket|whole foods|trader|safeway/
                     "Food & Dining"
    when /gas|shell|exxon|chevron|bp/
                     "Transportation"
    when /amazon|target|walmart|shopping/
                     "Shopping"
    when /netflix|spotify|hulu|entertainment/
                     "Entertainment"
    when /electric|water|gas|utility|phone|internet/
                     "Bills & Utilities"
    when /hospital|clinic|pharmacy|medical|health/
                     "Healthcare"
    else
                     is_income? ? "Income" : "Shopping" # Default categories
    end

    category = user.categories.find_by(name: category_name)
    if category
      transaction_classifications.create!(
        category: category,
        confidence_score: 0.7,
        auto_classified: true
      )
    end
  end
end
