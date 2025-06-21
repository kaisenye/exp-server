class CreateCategories < ActiveRecord::Migration[8.0]
  def change
    create_table :categories do |t|
      t.string :name, null: false
      t.string :description
      t.string :color, null: false
      t.references :user, null: false, foreign_key: true
      t.references :parent, foreign_key: { to_table: :categories }
      t.decimal :budget_limit, precision: 10, scale: 2

      t.timestamps
    end

    add_index :categories, [ :user_id, :name ], unique: true
  end
end
