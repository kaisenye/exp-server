FactoryBot.define do
  factory :insight do
    user { nil }
    title { "MyString" }
    description { "MyText" }
    insight_type { "MyString" }
    data { "" }
    created_for_period { "MyString" }
  end
end
