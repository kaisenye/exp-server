FactoryBot.define do
  factory :category do
    name { "MyString" }
    description { "MyString" }
    color { "MyString" }
    user { nil }
    parent { nil }
    budget_limit { "9.99" }
  end
end
