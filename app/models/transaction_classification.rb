class TransactionClassification < ApplicationRecord
  # Relationships
  belongs_to :expense_transaction, class_name: "Transaction", foreign_key: "transaction_id"
  belongs_to :category

  # Validations
  validates :confidence_score, presence: true,
            numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 }
  validates :transaction_id, uniqueness: { scope: :category_id }

  # Scopes
  scope :auto_classified, -> { where(auto_classified: true) }
  scope :manually_classified, -> { where(auto_classified: false) }
  scope :high_confidence, -> { where("confidence_score >= ?", 0.8) }
  scope :low_confidence, -> { where("confidence_score < ?", 0.5) }

  # Instance methods
  def confidence_percentage
    (confidence_score * 100).round(1)
  end
end
