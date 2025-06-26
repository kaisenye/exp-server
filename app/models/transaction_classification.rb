class TransactionClassification < ApplicationRecord
  # Relationships
  belongs_to :expense_transaction, class_name: "Transaction", foreign_key: "transaction_id"
  belongs_to :category

  # Validations
  validates :confidence_score, presence: true, inclusion: { in: 0.0..1.0 }
  validates :transaction_id, presence: true, uniqueness: true

  # Scopes
  scope :auto_classified, -> { where(auto_classified: true) }
  scope :manual, -> { where(auto_classified: false) }
  scope :high_confidence, -> { where("confidence_score >= ?", 0.8) }
  scope :low_confidence, -> { where("confidence_score < ?", 0.5) }

  # Instance methods
  def confidence_percentage
    (confidence_score * 100).round(1)
  end

  def confidence_level
    case confidence_score
    when 0.8..1.0
      "high"
    when 0.5...0.8
      "medium"
    else
      "low"
    end
  end
end
