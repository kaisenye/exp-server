class PlaidSyncJob < ApplicationJob
  queue_as :default

  def perform(user_id = nil, account_id = nil)
    if user_id.present?
      # Sync specific user's accounts
      sync_user_accounts(user_id)
    elsif account_id.present?
      # Sync specific account
      sync_single_account_by_id(account_id)
    else
      # Sync all users' accounts
      sync_all_accounts
    end
  end

  private

  def sync_user_accounts(user_id)
    user = User.find(user_id)
    plaid_accounts = user.accounts.where.not(plaid_access_token: [ nil, "" ])

    Rails.logger.info "Starting Plaid sync for user #{user.email} (#{plaid_accounts.count} accounts)"

    synced_count = 0
    error_count = 0

    plaid_accounts.find_each do |account|
      begin
        sync_account(account)
        synced_count += 1
      rescue => e
        Rails.logger.error "Failed to sync account #{account.display_name} for user #{user.email}: #{e.message}"
        error_count += 1
      end
    end

    Rails.logger.info "Completed Plaid sync for user #{user.email}: #{synced_count} synced, #{error_count} errors"
  end

  def sync_single_account_by_id(account_id)
    account = Account.find(account_id)

    unless account.plaid_access_token.present?
      Rails.logger.warn "Account #{account.display_name} is not linked to Plaid"
      return
    end

    sync_account(account)
  end

  def sync_all_accounts
    plaid_accounts = Account.where.not(plaid_access_token: [ nil, "" ])

    Rails.logger.info "Starting bulk Plaid sync for #{plaid_accounts.count} accounts"

    synced_count = 0
    error_count = 0

    plaid_accounts.find_each do |account|
      begin
        sync_account(account)
        synced_count += 1
      rescue => e
        Rails.logger.error "Failed to sync account #{account.display_name}: #{e.message}"
        error_count += 1
      end

      # Add small delay to avoid rate limiting
      sleep(0.5)
    end

    Rails.logger.info "Completed bulk Plaid sync: #{synced_count} synced, #{error_count} errors"
  end

  def sync_account(account)
    # Fetch recent transactions (last 30 days)
    plaid_transactions = PlaidService.fetch_recent_transactions(account.plaid_access_token)

    # Sync account balance first
    plaid_accounts = PlaidService.fetch_accounts(account.plaid_access_token)
    plaid_account = plaid_accounts.find { |acc| acc[:plaid_account_id] == account.plaid_account_id }

    if plaid_account
      account.update!(
        balance_current: plaid_account[:balance_current],
        balance_available: plaid_account[:balance_available],
        last_sync_at: Time.current
      )
    end

    # Create or update transactions
    transactions_created = 0
    transactions_updated = 0

    plaid_transactions.each do |plaid_transaction|
      # Only process transactions for this account
      next unless plaid_transaction[:plaid_account_id] == account.plaid_account_id

      transaction = account.transactions.find_or_initialize_by(
        plaid_transaction_id: plaid_transaction[:plaid_transaction_id]
      )

      if transaction.new_record?
        transaction.assign_attributes(
          amount: plaid_transaction[:amount],
          currency: plaid_transaction[:currency],
          date: plaid_transaction[:date],
          merchant_name: plaid_transaction[:merchant_name],
          description: plaid_transaction[:description],
          category: plaid_transaction[:category],
          subcategory: plaid_transaction[:subcategory],
          pending: plaid_transaction[:pending]
        )
        transaction.save!
        transactions_created += 1

        # Auto-classify new transactions
        auto_classify_transaction(transaction)
      else
        # Update existing transaction (amounts, pending status might change)
        if transaction.amount != plaid_transaction[:amount] ||
           transaction.pending != plaid_transaction[:pending]
          transaction.update!(
            amount: plaid_transaction[:amount],
            pending: plaid_transaction[:pending]
          )
          transactions_updated += 1
        end
      end
    end

    Rails.logger.info "Synced account #{account.display_name}: #{transactions_created} created, #{transactions_updated} updated"
  end

  def auto_classify_transaction(transaction)
    # Use the enhanced classification logic from TransactionsController
    transactions_controller = Api::V1::TransactionsController.new

    # Find matching category using enhanced logic
    category = transactions_controller.send(:find_matching_category, transaction)

    if category
      # Create classification with confidence based on matching method
      confidence = calculate_confidence(transaction, category)

      TransactionClassification.find_or_create_by(
        transaction_id: transaction.id,
        category: category
      ) do |classification|
        classification.confidence_score = confidence
        classification.auto_classified = true  # Auto-classified, not user-confirmed
      end

      Rails.logger.info "Auto-classified transaction #{transaction.id} to category '#{category.name}' with confidence #{confidence}"
    else
      Rails.logger.info "Could not auto-classify transaction #{transaction.id}: #{transaction.description}"
    end
  end

  private

  def calculate_confidence(transaction, category)
    # Higher confidence for Plaid category matches
    if transaction.subcategory.present? &&
       category.name.downcase.include?(transaction.subcategory.downcase)
      return 0.95  # Very high confidence for subcategory match
    end

    if transaction.category.present? &&
       category.name.downcase.include?(transaction.category.downcase)
      return 0.90  # High confidence for category match
    end

    # Medium confidence for merchant/description matches
    if transaction.merchant_name.present? &&
       (category.name.downcase.include?(transaction.merchant_name.downcase.split.first) ||
        category.description&.downcase&.include?(transaction.merchant_name.downcase))
      return 0.85
    end

    # Lower confidence for keyword matches
    0.75
  end
end
