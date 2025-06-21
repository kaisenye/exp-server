class CreateTransactionClassifications < ActiveRecord::Migration[8.0]
  def change
    create_table :transaction_classifications do |t|
      t.integer :transaction_id
      t.integer :category_id
      t.decimal :confidence_score
      t.boolean :auto_classified

      t.timestamps
    end
  end
end
