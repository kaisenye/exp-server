class CreateTransactions < ActiveRecord::Migration[8.0]
  def change
    create_table :transactions do |t|
      t.references :account, null: false, foreign_key: true
      t.string :plaid_transaction_id
      t.decimal :amount
      t.string :currency
      t.date :date
      t.string :merchant_name
      t.string :description
      t.string :category
      t.string :subcategory
      t.boolean :pending

      t.timestamps
    end
  end
end
