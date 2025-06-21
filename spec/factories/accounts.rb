FactoryBot.define do
  factory :account do
    user { nil }
    account_type { "MyString" }
    name { "MyString" }
    institution_name { "MyString" }
    plaid_account_id { "MyString" }
    plaid_access_token { "MyString" }
    balance_current { "9.99" }
    balance_available { "9.99" }
    currency { "MyString" }
    last_sync_at { "2025-06-21 10:59:16" }
    active { false }
  end
end
