class Category < ApplicationRecord
  # Relationships
  belongs_to :user
  belongs_to :parent_category, class_name: "Category", foreign_key: "parent_id", optional: true
  has_many :subcategories, class_name: "Category", foreign_key: "parent_id"
  has_many :transaction_classifications, dependent: :destroy
  has_many :transactions, through: :transaction_classifications, source: :expense_transaction

  # Validations
  validates :name, presence: true, uniqueness: { scope: :user_id }
  validates :color, presence: true, format: { with: /\A#[a-fA-F0-9]{6}\z/ }

  # Scopes
  scope :top_level, -> { where(parent_id: nil) }
  scope :with_budget, -> { where.not(budget_limit: nil) }

  # Instance methods
  def has_children?
    subcategories.any?
  end

  def total_spent_this_month
    start_date = Date.current.beginning_of_month
    end_date = Date.current.end_of_month

    transactions.joins(:account)
                .where(accounts: { user_id: user_id })
                .by_date_range(start_date, end_date)
                .expenses
                .sum(:amount)
                .abs
  end

  def budget_remaining
    return nil unless budget_limit
    budget_limit - total_spent_this_month
  end

  def budget_percentage_used
    return 0 unless budget_limit && budget_limit > 0
    ((total_spent_this_month / budget_limit) * 100).round
  end

  def over_budget?
    budget_limit && total_spent_this_month > budget_limit
  end

  def full_name
    parent_category ? "#{parent_category.name} > #{name}" : name
  end
end
