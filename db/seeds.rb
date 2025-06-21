# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end

# Create sample users
puts "Creating sample users..."

demo_user = User.find_or_create_by(email: "demo@example.com") do |user|
  user.password = "password123"
  user.password_confirmation = "password123"
  user.first_name = "Demo"
  user.last_name = "User"
end

puts "Created demo user: #{demo_user.email}"

# Create default categories for the demo user
puts "Creating default categories..."

categories_data = [
  { name: "Food & Dining", color: "#FF6B6B", subcategories: [ "Restaurants", "Groceries", "Coffee & Tea", "Fast Food" ] },
  { name: "Transportation", color: "#4ECDC4", subcategories: [ "Gas", "Public Transit", "Ride Share", "Parking" ] },
  { name: "Shopping", color: "#45B7D1", subcategories: [ "Clothing", "Electronics", "Home & Garden", "General" ] },
  { name: "Entertainment", color: "#FFA07A", subcategories: [ "Movies", "Music", "Games", "Sports" ] },
  { name: "Bills & Utilities", color: "#98D8C8", subcategories: [ "Electricity", "Water", "Internet", "Phone" ] },
  { name: "Health & Fitness", color: "#F7DC6F", subcategories: [ "Medical", "Pharmacy", "Gym", "Wellness" ] },
  { name: "Travel", color: "#BB8FCE", subcategories: [ "Hotels", "Flights", "Car Rental", "Activities" ] },
  { name: "Education", color: "#85C1E9", subcategories: [ "Books", "Courses", "Supplies", "Tuition" ] },
  { name: "Income", color: "#82E0AA", subcategories: [ "Salary", "Freelance", "Investment", "Other" ] },
  { name: "Savings", color: "#F8C471", subcategories: [ "Emergency Fund", "Vacation", "Retirement", "Investment" ] }
]

categories_data.each do |cat_data|
  parent_category = Category.find_or_create_by(
    user: demo_user,
    name: cat_data[:name]
  ) do |category|
    category.color = cat_data[:color]
    category.description = "#{cat_data[:name]} related expenses"
    category.budget_limit = rand(200..1000) # Random budget between $200-$1000
  end

  # Create subcategories
  cat_data[:subcategories].each do |sub_name|
    Category.find_or_create_by(
      user: demo_user,
      name: sub_name,
      parent: parent_category
    ) do |subcategory|
      subcategory.color = cat_data[:color]
      subcategory.description = "#{sub_name} expenses under #{cat_data[:name]}"
    end
  end
end

puts "Created #{Category.where(user: demo_user).count} categories for demo user"

# Create sample accounts
puts "Creating sample accounts..."

sample_accounts = [
  {
    name: "Chase Checking",
    account_type: "checking",
    institution_name: "Chase Bank",
    plaid_account_id: "demo_checking_account_001",
    balance_current: 2500.00,
    balance_available: 2500.00,
    currency: "USD",
    active: true
  },
  {
    name: "Chase Savings",
    account_type: "savings",
    institution_name: "Chase Bank",
    plaid_account_id: "demo_savings_account_002",
    balance_current: 10000.00,
    balance_available: 10000.00,
    currency: "USD",
    active: true
  },
  {
    name: "Chase Freedom Credit Card",
    account_type: "credit_card",
    institution_name: "Chase Bank",
    plaid_account_id: "demo_credit_account_003",
    balance_current: -850.00,
    balance_available: 4150.00,
    currency: "USD",
    active: true
  }
]

sample_accounts.each do |account_data|
  Account.find_or_create_by(
    user: demo_user,
    plaid_account_id: account_data[:plaid_account_id]
  ) do |account|
    account.name = account_data[:name]
    account.account_type = account_data[:account_type]
    account.institution_name = account_data[:institution_name]
    account.balance_current = account_data[:balance_current]
    account.balance_available = account_data[:balance_available]
    account.currency = account_data[:currency]
    account.active = account_data[:active]
    account.last_sync_at = 1.day.ago
  end
end

puts "Created #{Account.where(user: demo_user).count} accounts for demo user"

# Create sample transactions
puts "Creating sample transactions..."

if demo_user.accounts.any?
  checking_account = demo_user.accounts.find_by(account_type: "checking")
  credit_account = demo_user.accounts.find_by(account_type: "credit_card")

  sample_transactions = [
    { account: checking_account, amount: -45.67, description: "Whole Foods Market", date: 2.days.ago, category: "Groceries" },
    { account: credit_account, amount: -12.50, description: "Starbucks Coffee", date: 1.day.ago, category: "Coffee & Tea" },
    { account: checking_account, amount: -75.00, description: "Shell Gas Station", date: 3.days.ago, category: "Gas" },
    { account: credit_account, amount: -89.99, description: "Amazon Purchase", date: 1.week.ago, category: "Shopping" },
    { account: checking_account, amount: 3000.00, description: "Salary Deposit", date: 1.week.ago, category: "Salary" },
    { account: credit_account, amount: -25.00, description: "Netflix Subscription", date: 2.weeks.ago, category: "Entertainment" },
    { account: checking_account, amount: -120.00, description: "Electric Bill", date: 1.week.ago, category: "Electricity" }
  ]

  sample_transactions.each_with_index do |trans_data, index|
    next unless trans_data[:account]

    transaction = Transaction.find_or_create_by(
      account: trans_data[:account],
      plaid_transaction_id: "demo_transaction_#{index + 1}"
    ) do |t|
      t.amount = trans_data[:amount]
      t.description = trans_data[:description]
      t.date = trans_data[:date]
      t.currency = "USD"
      t.pending = false
      t.merchant_name = trans_data[:description].split(' ').first
    end

    # Auto-classify the transaction
    if transaction.persisted?
      category = Category.joins(:parent).find_by(
        user: demo_user,
        name: trans_data[:category]
      ) || Category.find_by(user: demo_user, name: trans_data[:category])

      if category
        TransactionClassification.find_or_create_by(
          transaction_id: transaction.id,
          category: category
        ) do |classification|
          classification.confidence_score = 0.9
          classification.auto_classified = true
        end
      end
    end
  end
end

puts "Created sample transactions with classifications"

puts "Seed data creation completed!"
puts "Demo user credentials:"
puts "  Email: demo@example.com"
puts "  Password: password123"
