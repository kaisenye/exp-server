class AddPlaidFieldsToAccounts < ActiveRecord::Migration[8.0]
  def change
    add_column :accounts, :plaid_item_id, :string
    add_column :accounts, :sync_status, :string
    add_column :accounts, :last_error_at, :datetime
    add_column :accounts, :display_name, :string
  end
end
