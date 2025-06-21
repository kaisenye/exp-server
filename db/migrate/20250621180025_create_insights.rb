class CreateInsights < ActiveRecord::Migration[8.0]
  def change
    create_table :insights do |t|
      t.references :user, null: false, foreign_key: true
      t.string :title
      t.text :description
      t.string :insight_type
      t.json :data
      t.string :created_for_period

      t.timestamps
    end
  end
end
