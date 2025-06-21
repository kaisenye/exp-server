class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable,
         :jwt_authenticatable, jwt_revocation_strategy: JwtDenylist

  # Relationships
  has_many :accounts, dependent: :destroy
  has_many :transactions, through: :accounts
  has_many :categories, dependent: :destroy
  has_many :insights, dependent: :destroy

  # Validations
  validates :email, presence: true, uniqueness: true
  validates :first_name, :last_name, presence: true

  # Callbacks
  after_create :create_default_categories

  private

  def create_default_categories
    default_categories = [
      { name: "Food & Dining", description: "Restaurants, groceries, takeout", color: "#FF6B6B" },
      { name: "Transportation", description: "Gas, public transit, rideshare", color: "#4ECDC4" },
      { name: "Shopping", description: "Clothes, electronics, general shopping", color: "#45B7D1" },
      { name: "Entertainment", description: "Movies, concerts, subscriptions", color: "#96CEB4" },
      { name: "Bills & Utilities", description: "Rent, electricity, phone, internet", color: "#FFEAA7" },
      { name: "Healthcare", description: "Medical, dental, pharmacy", color: "#DDA0DD" },
      { name: "Income", description: "Salary, freelance, other income", color: "#98D8C8" }
    ]

    default_categories.each do |cat_attrs|
      categories.create!(cat_attrs)
    end
  end
end
