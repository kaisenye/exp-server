class Api::V1::PlaidController < Api::V1::BaseController
  # POST /api/v1/plaid/link_token
  def create_link_token
    begin
      Rails.logger.info "Creating Plaid link token for user: #{current_user.id}"
      link_token = PlaidService.create_link_token(current_user.id)
      Rails.logger.info "Successfully created Plaid link token"

      render json: {
        link_token: link_token,
        message: "Link token created successfully"
      }
    rescue PlaidError => e
      Rails.logger.error "PlaidError in create_link_token: #{e.message}"
      render json: {
        error: "Failed to create link token",
        details: e.message
      }, status: :unprocessable_entity
    rescue => e
      Rails.logger.error "Unexpected error in create_link_token: #{e.message}"
      Rails.logger.error "Backtrace: #{e.backtrace.join("\n")}"
      render json: {
        error: "Failed to create link token",
        details: "Unexpected error occurred"
      }, status: :internal_server_error
    end
  end

  # POST /api/v1/plaid/exchange_token
  def exchange_token
    public_token = params[:public_token]
    return render json: { error: "Public token is required" }, status: :bad_request unless public_token

    # Exchange public token for access token
    token_response = PlaidService.exchange_public_token(public_token)
    access_token = token_response[:access_token]
    item_id = token_response[:item_id]

    # Fetch accounts from Plaid
    plaid_accounts = PlaidService.fetch_accounts(access_token)

    # Create account records for the user
    created_accounts = []
    plaid_accounts.each do |plaid_account|
      account = current_user.accounts.create!(
        plaid_account_id: plaid_account[:plaid_account_id],
        plaid_access_token: access_token,
        plaid_item_id: item_id,
        account_type: map_plaid_account_type(plaid_account[:type], plaid_account[:subtype]),
        name: plaid_account[:name],
        display_name: plaid_account[:name],
        institution_name: plaid_account[:institution_name],
        balance_current: plaid_account[:balance_current],
        balance_available: plaid_account[:balance_available],
        currency: plaid_account[:currency] || "USD",
        active: true,
        sync_status: "connected",
        last_sync_at: Time.current
      )
      created_accounts << account
    end

    # Sync recent transactions for new accounts
    sync_accounts_transactions(created_accounts)

    render json: {
      message: "Accounts linked successfully",
      accounts: created_accounts.map { |account| account_response_data(account) }
    }
  rescue PlaidError => e
    render json: { error: e.message }, status: :unprocessable_entity
  rescue => e
    Rails.logger.error "Error in exchange_token: #{e.message}"
    render json: { error: "Failed to link accounts" }, status: :internal_server_error
  end

  # POST /api/v1/plaid/sync/:account_id
  def sync_account
    @account = current_user.accounts.find(params[:account_id])

    unless @account.plaid_access_token.present?
      return render json: {
        error: "Account is not linked to Plaid"
      }, status: :unprocessable_entity
    end

    begin
      # Sync transactions for the last 30 days
      sync_single_account(@account)

      render json: {
        message: "Account synchronized successfully",
        account: account_response_data(@account.reload),
        last_sync_at: @account.last_sync_at
      }
    rescue PlaidError => e
      render json: {
        error: "Failed to sync account",
        details: e.message
      }, status: :unprocessable_entity
    end
  rescue ActiveRecord::RecordNotFound
    render json: {
      error: "Account not found"
    }, status: :not_found
  end

  # POST /api/v1/plaid/sync_all
  def sync_all_accounts
    plaid_accounts = current_user.accounts.where.not(encrypted_plaid_access_token: [ nil, "" ])

    if plaid_accounts.empty?
      return render json: {
        message: "No Plaid-linked accounts found",
        accounts_synced: 0
      }
    end

    synced_count = 0
    errors = []

    plaid_accounts.each do |account|
      begin
        sync_single_account(account)
        synced_count += 1
      rescue PlaidError => e
        errors << {
          account_id: account.id,
          account_name: account.display_name,
          error: e.message
        }
      end
    end

    render json: {
      message: "Bulk sync completed",
      accounts_synced: synced_count,
      total_plaid_accounts: plaid_accounts.count,
      errors: errors
    }
  end

  # GET /api/v1/plaid/status
  def status
    accounts = current_user.accounts.where.not(encrypted_plaid_access_token: [ nil, "" ])

    render json: {
      linked_accounts: accounts.count,
      accounts: accounts.map { |account| account_response_data(account) },
      last_sync: accounts.maximum(:last_sync_at)
    }
  rescue => e
    Rails.logger.error "Error fetching Plaid status: #{e.message}"
    render json: { error: "Failed to fetch status" }, status: :internal_server_error
  end

  # POST /api/v1/plaid/webhook
  def webhook
    # Verify webhook signature (in production, verify with Plaid webhook secret)
    webhook_type = params[:webhook_type]
    webhook_code = params[:webhook_code]
    item_id = params[:item_id]

    case webhook_type
    when "TRANSACTIONS"
      handle_transactions_webhook(webhook_code, item_id)
    when "ITEM"
      handle_item_webhook(webhook_code, item_id)
    when "ASSETS"
      handle_assets_webhook(webhook_code, item_id)
    else
      Rails.logger.warn "Unhandled webhook type: #{webhook_type}"
    end

    render json: { status: "received" }
  rescue => e
    Rails.logger.error "Error handling webhook: #{e.message}"
    render json: { error: "Webhook processing failed" }, status: :internal_server_error
  end

  # POST /api/v1/plaid/sync_jobs
  def schedule_sync
    job_type = params[:job_type] || "all"

    case job_type
    when "user"
      PlaidSyncJob.perform_later(current_user.id)
      message = "Scheduled sync for your accounts"
    when "account"
      account_id = params[:account_id]
      return render json: { error: "Account ID required" }, status: :bad_request unless account_id

      PlaidSyncJob.perform_later(nil, account_id)
      message = "Scheduled sync for account #{account_id}"
    when "all"
      # Only allow admin users to sync all accounts
      return render json: { error: "Unauthorized" }, status: :forbidden unless current_user.admin?

      PlaidSyncJob.perform_later
      message = "Scheduled sync for all accounts"
    else
      return render json: { error: "Invalid job type" }, status: :bad_request
    end

    render json: { message: message, job_type: job_type }
  rescue => e
    Rails.logger.error "Error scheduling sync job: #{e.message}"
    render json: { error: "Failed to schedule sync" }, status: :internal_server_error
  end

  private

  def sync_single_account(account)
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
        transaction.update!(
          amount: plaid_transaction[:amount],
          pending: plaid_transaction[:pending]
        )
        transactions_updated += 1
      end
    end

    Rails.logger.info "Synced account #{account.display_name}: #{transactions_created} created, #{transactions_updated} updated"
  end

  def sync_accounts_transactions(accounts)
    accounts.each do |account|
      begin
        sync_single_account(account)
      rescue => e
        Rails.logger.error "Failed to sync account #{account.display_name}: #{e.message}"
        account.update(sync_status: "error", last_error_at: Time.current)
      end
    end
  end

  def auto_classify_transaction(transaction)
    # Simple auto-classification based on description and Plaid category
    category = find_matching_category(transaction)

    if category
      transaction.transaction_classifications.create!(
        category: category,
        confidence_score: 0.8, # Auto-classification confidence
        auto_classified: true
      )
    end
  end

  def find_matching_category(transaction)
    user = transaction.account.user

    # Try to match by Plaid category first
    if transaction.category.present?
      category = user.categories.where(
        "LOWER(name) LIKE ?",
        "%#{transaction.category.downcase}%"
      ).first
      return category if category
    end

    # Try to match by description keywords
    description_lower = transaction.description.downcase

    # Common patterns for auto-classification
    category_patterns = {
      "gas" => [ "gas", "fuel", "chevron", "shell", "exxon" ],
      "grocery" => [ "grocery", "market", "food", "kroger", "safeway" ],
      "restaurant" => [ "restaurant", "cafe", "mcdonald", "starbucks" ],
      "entertainment" => [ "movie", "theater", "netflix", "spotify" ],
      "shopping" => [ "amazon", "target", "walmart", "store" ]
    }

    category_patterns.each do |category_name, keywords|
      if keywords.any? { |keyword| description_lower.include?(keyword) }
        category = user.categories.where("LOWER(name) LIKE ?", "%#{category_name}%").first
        return category if category
      end
    end

    nil
  end

  def map_plaid_account_type(type, subtype)
    case type.downcase
    when "depository"
      case subtype&.downcase
      when "checking"
        "checking"
      when "savings"
        "savings"
      else
        "checking" # Default for depository
      end
    when "credit"
      "credit_card"
    when "investment"
      "investment"
    when "loan"
      "loan"
    else
      "checking" # Default fallback
    end
  end

  def account_response_data(account)
    {
      id: account.id,
      name: account.name,
      account_type: account.account_type,
      institution_name: account.institution_name,
      balance_current: account.balance_current,
      balance_available: account.balance_available,
      balance_display: account.balance_display,
      formatted_balance: account.formatted_balance,
      currency: account.currency,
      last_sync_at: account.last_sync_at,
      active: account.active,
      display_name: account.display_name,
      needs_sync: account.needs_sync?,
      created_at: account.created_at,
      updated_at: account.updated_at
    }
  end

  def handle_transactions_webhook(code, item_id)
    case code
    when "INITIAL_UPDATE", "HISTORICAL_UPDATE", "DEFAULT_UPDATE"
      # Find accounts associated with this item
      accounts = Account.where(plaid_item_id: item_id)

      if accounts.any?
        # Schedule sync jobs for each account
        accounts.each do |account|
          PlaidSyncJob.perform_later(nil, account.id)
        end
        Rails.logger.info "Scheduled sync jobs for #{accounts.count} accounts (item: #{item_id})"
      else
        Rails.logger.warn "No accounts found for item: #{item_id}"
      end
    when "TRANSACTIONS_REMOVED"
      # Handle removed transactions (implement if needed)
      Rails.logger.info "Transactions removed webhook received for item: #{item_id}"
    else
      Rails.logger.warn "Unhandled transactions webhook code: #{code}"
    end
  end

  def handle_item_webhook(code, item_id)
    case code
    when "ERROR"
      # Handle item errors (e.g., expired token, requires user intervention)
      accounts = Account.where(plaid_item_id: item_id)
      accounts.update_all(sync_status: "error", last_error_at: Time.current)
      Rails.logger.error "Item error for item: #{item_id}"
    when "PENDING_EXPIRATION"
      # Notify users about pending token expiration
      Rails.logger.warn "Token pending expiration for item: #{item_id}"
    else
      Rails.logger.warn "Unhandled item webhook code: #{code}"
    end
  end

  def handle_assets_webhook(code, item_id)
    # Handle assets webhooks if using Plaid Assets product
    Rails.logger.info "Assets webhook received: #{code} for item: #{item_id}"
  end
end
