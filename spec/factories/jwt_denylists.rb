FactoryBot.define do
  factory :jwt_denylist do
    jti { "MyString" }
    exp { "2025-06-21 11:02:58" }
  end
end
