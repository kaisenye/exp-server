class AddEncryptedPlaidAccessTokenToAccounts < ActiveRecord::Migration[8.0]
  def up
    # Add encrypted columns
    add_column :accounts, :encrypted_plaid_access_token, :text
    add_column :accounts, :encrypted_plaid_access_token_iv, :string

    # Create a temporary model without attr_encrypted to access plain text data
    temp_account_class = Class.new(ActiveRecord::Base) do
      self.table_name = 'accounts'
    end

    # Migrate existing plain text tokens to encrypted format
    temp_account_class.where.not(plaid_access_token: [ nil, '' ]).find_each do |account|
      # Use the Account model with attr_encrypted to encrypt the token
      real_account = Account.find(account.id)

      # Set the plain text token, which will be encrypted automatically
      real_account.plaid_access_token = account.plaid_access_token
      real_account.save!
    end

    # Remove the old plain text column
    remove_column :accounts, :plaid_access_token
  end

  def down
    # Add back the plain text column
    add_column :accounts, :plaid_access_token, :string

    # Decrypt existing tokens back to plain text
    Account.where.not(encrypted_plaid_access_token: [ nil, '' ]).find_each do |account|
      if account.plaid_access_token.present?
        account.update_column(:plaid_access_token, account.plaid_access_token)
      end
    end

    # Remove encrypted columns
    remove_column :accounts, :encrypted_plaid_access_token
    remove_column :accounts, :encrypted_plaid_access_token_iv
  end
end
