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

    # TODO: Implement Plaid sync logic here
    # For now, just update the last_sync_at timestamp
    @account.update!(last_sync_at: Time.current)

    render json: {
      message: "Account sync initiated",
      account: account_response_data(@account)
    }
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
