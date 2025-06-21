class CreateAccounts < ActiveRecord::Migration[8.0]
  def change
    create_table :accounts do |t|
      t.references :user, null: false, foreign_key: true
      t.string :account_type
      t.string :name
      t.string :institution_name
      t.string :plaid_account_id
      t.string :plaid_access_token
      t.decimal :balance_current
      t.decimal :balance_available
      t.string :currency
      t.datetime :last_sync_at
      t.boolean :active

      t.timestamps
    end
  end
end
