FactoryBot.define do
  factory :transaction do
    account { nil }
    plaid_transaction_id { "MyString" }
    amount { "9.99" }
    currency { "MyString" }
    date { "2025-06-21" }
    merchant_name { "MyString" }
    description { "MyString" }
    category { "MyString" }
    subcategory { "MyString" }
    pending { false }
  end
end
