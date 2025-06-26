class Api::V1::AccountsController < Api::V1::BaseController
  before_action :set_account, only: [ :show, :update, :destroy ]

  # GET /api/v1/accounts
  def index
    @accounts = current_user.accounts.active.includes(:transactions)

    accounts_data = @accounts.map do |account|
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
        transaction_count: account.transactions.count,
        created_at: account.created_at,
        updated_at: account.updated_at
      }
    end

    render json: {
      accounts: accounts_data,
      total_balance: calculate_total_balance(@accounts)
    }
  end

  # GET /api/v1/accounts/:id
  def show
    account_data = {
      id: @account.id,
      name: @account.name,
      account_type: @account.account_type,
      institution_name: @account.institution_name,
      balance_current: @account.balance_current,
      balance_available: @account.balance_available,
      balance_display: @account.balance_display,
      formatted_balance: @account.formatted_balance,
      currency: @account.currency,
      last_sync_at: @account.last_sync_at,
      active: @account.active,
      display_name: @account.display_name,
      needs_sync: @account.needs_sync?,
      transaction_count: @account.transactions.count,
      recent_transactions: recent_transactions_data(@account),
      created_at: @account.created_at,
      updated_at: @account.updated_at
    }

    render json: { account: account_data }
  end

  # POST /api/v1/accounts
  def create
    @account = current_user.accounts.build(account_params)

    # Set default values for new accounts
    @account.active = true
    @account.currency = "USD" if @account.currency.blank?
    @account.last_sync_at = Time.current

    if @account.save
      render json: {
        message: "Account created successfully",
        account: account_response_data(@account)
      }, status: :created
    else
      render json: {
        error: "Failed to create account",
        details: @account.errors.full_messages
      }, status: :unprocessable_entity
    end
  end

  # PUT /api/v1/accounts/:id
  def update
    if @account.update(account_update_params)
      render json: {
        message: "Account updated successfully",
        account: account_response_data(@account)
      }
    else
      render json: {
        error: "Failed to update account",
        details: @account.errors.full_messages
      }, status: :unprocessable_entity
    end
  end

  # DELETE /api/v1/accounts/:id
  def destroy
    # Instead of hard delete, we'll soft delete by setting active to false
    if @account.update(active: false)
      render json: {
        message: "Account deactivated successfully"
      }
    else
      render json: {
        error: "Failed to deactivate account"
      }, status: :unprocessable_entity
    end
  end

  # POST /api/v1/accounts/:id/sync
  def sync
    @account = current_user.accounts.find(params[:id])

    # Check if account is linked to Plaid
    unless @account.plaid_access_token.present?
      return render json: {
        error: "Account is not linked to Plaid",
        suggestion: "Use the Plaid link flow to connect this account"
      }, status: :unprocessable_entity
    end

    begin
      # Use PlaidService to sync the account
      sync_single_account(@account)

      render json: {
        message: "Account sync completed successfully",
        account: account_response_data(@account.reload),
        last_sync_at: @account.last_sync_at
      }
    rescue PlaidError => e
      render json: {
        error: "Failed to sync account with Plaid",
        details: e.message
      }, status: :unprocessable_entity
    rescue => e
      Rails.logger.error "Account sync error: #{e.message}"
      render json: {
        error: "Sync failed due to an unexpected error",
        details: e.message
      }, status: :internal_server_error
    end
  rescue ActiveRecord::RecordNotFound
    render json: {
      error: "Account not found"
    }, status: :not_found
  end

  private

  def set_account
    @account = current_user.accounts.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render json: {
      error: "Account not found"
    }, status: :not_found
  end

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

  def account_params
    params.require(:account).permit(
      :name,
      :account_type,
      :institution_name,
      :plaid_account_id,
      :balance_current,
      :balance_available,
      :currency
    )
  end

  def account_update_params
    params.require(:account).permit(
      :name,
      :institution_name,
      :active
    )
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

  def recent_transactions_data(account)
    account.transactions.recent.limit(10).map do |transaction|
      {
        id: transaction.id,
        amount: transaction.amount,
        formatted_amount: transaction.formatted_amount,
        description: transaction.description,
        date: transaction.date,
        pending: transaction.pending,
        primary_category: transaction.primary_category&.name
      }
    end
  end

  def calculate_total_balance(accounts)
    total = accounts.sum do |account|
      if account.account_type == "credit_card"
        # For credit cards, we want to show debt as negative
        account.balance_current || 0
      else
        account.balance_current || 0
      end
    end

    {
      amount: total,
      formatted: "$%.2f" % total.abs,
      is_negative: total < 0
    }
  end
end
