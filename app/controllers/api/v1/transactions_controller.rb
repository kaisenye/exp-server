class Api::V1::TransactionsController < Api::V1::BaseController
  before_action :set_transaction, only: [ :show, :categorize ]

  # GET /api/v1/transactions
  def index
    @transactions = current_user.transactions.includes(:account, :transaction_classifications, :categories)

    # Apply filters
    @transactions = apply_filters(@transactions)

    # Pagination
    page = params[:page]&.to_i || 1
    per_page = params[:per_page]&.to_i || 20
    per_page = [ per_page, 100 ].min # Max 100 per page

    @transactions = @transactions.offset((page - 1) * per_page).limit(per_page)

    transactions_data = @transactions.map do |transaction|
      transaction_response_data(transaction)
    end

    # Get total count for pagination
    total_count = current_user.transactions.count
    total_pages = (total_count.to_f / per_page).ceil

    render json: {
      transactions: transactions_data,
      pagination: {
        current_page: page,
        per_page: per_page,
        total_count: total_count,
        total_pages: total_pages
      },
      summary: transactions_summary
    }
  end

  # GET /api/v1/transactions/:id
  def show
    render json: {
      transaction: transaction_detail_data(@transaction)
    }
  end

  # POST /api/v1/transactions/sync
  def sync
    account_id = params[:account_id]

    if account_id.present?
      # Sync specific account
      @account = current_user.accounts.find(account_id)
      sync_account_transactions(@account)
      message = "Transactions synced for #{@account.display_name}"
    else
      # Sync all accounts
      synced_count = 0
      current_user.accounts.active.each do |account|
        sync_account_transactions(account)
        synced_count += 1
      end
      message = "Transactions synced for #{synced_count} accounts"
    end

    render json: {
      message: message,
      last_sync_at: Time.current
    }
  rescue ActiveRecord::RecordNotFound
    render json: {
      error: "Account not found"
    }, status: :not_found
  end

  # PUT /api/v1/transactions/:id/categorize
  def categorize
    category_id = params[:category_id]
    confidence_score = params[:confidence_score]&.to_f || 1.0

    unless category_id.present?
      return render json: {
        error: "Category ID is required"
      }, status: :unprocessable_entity
    end

    # Verify category belongs to user
    category = current_user.categories.find(category_id)

    # Remove existing classifications for this transaction
    @transaction.transaction_classifications.destroy_all

    # Create new classification
    classification = @transaction.transaction_classifications.create!(
      category: category,
      confidence_score: confidence_score,
      auto_classified: false
    )

    render json: {
      message: "Transaction categorized successfully",
      transaction: transaction_response_data(@transaction.reload),
      classification: {
        id: classification.id,
        category: {
          id: category.id,
          name: category.name,
          color: category.color,
          full_name: category.full_name
        },
        confidence_score: classification.confidence_score,
        confidence_percentage: classification.confidence_percentage,
        auto_classified: classification.auto_classified
      }
    }
  rescue ActiveRecord::RecordNotFound
    render json: {
      error: "Category not found"
    }, status: :not_found
  rescue ActiveRecord::RecordInvalid => e
    render json: {
      error: "Failed to categorize transaction",
      details: e.record.errors.full_messages
    }, status: :unprocessable_entity
  end

  # GET /api/v1/transactions/uncategorized
  def uncategorized
    @transactions = current_user.transactions
                                .left_joins(:transaction_classifications)
                                .where(transaction_classifications: { id: nil })
                                .includes(:account)
                                .recent
                                .limit(50)

    transactions_data = @transactions.map do |transaction|
      transaction_response_data(transaction)
    end

    render json: {
      transactions: transactions_data,
      count: @transactions.count,
      message: "Uncategorized transactions (up to 50 most recent)"
    }
  end

  # GET /api/v1/transactions/by_category/:category_id
  def by_category
    category = current_user.categories.find(params[:category_id])

    @transactions = category.transactions
                           .joins(:account)
                           .where(accounts: { user_id: current_user.id })
                           .includes(:account, :transaction_classifications)
                           .recent
                           .limit(100)

    transactions_data = @transactions.map do |transaction|
      transaction_response_data(transaction)
    end

    render json: {
      category: {
        id: category.id,
        name: category.name,
        full_name: category.full_name,
        color: category.color
      },
      transactions: transactions_data,
      count: @transactions.count,
      total_spent: @transactions.expenses.sum(:amount).abs,
      total_income: @transactions.income.sum(:amount)
    }
  rescue ActiveRecord::RecordNotFound
    render json: {
      error: "Category not found"
    }, status: :not_found
  end

  private

  def set_transaction
    @transaction = current_user.transactions.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render json: {
      error: "Transaction not found"
    }, status: :not_found
  end

  def apply_filters(transactions)
    # Filter by date range
    if params[:start_date].present? && params[:end_date].present?
      start_date = Date.parse(params[:start_date])
      end_date = Date.parse(params[:end_date])
      transactions = transactions.by_date_range(start_date, end_date)
    end

    # Filter by account
    if params[:account_id].present?
      transactions = transactions.where(account_id: params[:account_id])
    end

    # Filter by category
    if params[:category_id].present?
      transactions = transactions.joins(:transaction_classifications)
                                .where(transaction_classifications: { category_id: params[:category_id] })
    end

    # Filter by transaction type
    case params[:type]
    when "expenses"
      transactions = transactions.expenses
    when "income"
      transactions = transactions.income
    end

    # Filter by pending status
    case params[:pending]
    when "true"
      transactions = transactions.pending
    when "false"
      transactions = transactions.settled
    end

    # Search by description or merchant
    if params[:search].present?
      search_term = "%#{params[:search].downcase}%"
      transactions = transactions.where(
        "LOWER(description) LIKE ? OR LOWER(merchant_name) LIKE ?",
        search_term, search_term
      )
    end

    # Sort
    case params[:sort]
    when "amount_asc"
      transactions = transactions.order(:amount)
    when "amount_desc"
      transactions = transactions.order(amount: :desc)
    when "date_asc"
      transactions = transactions.order(:date)
    else
      transactions = transactions.recent # Default: date desc
    end

    transactions
  rescue Date::Error
    transactions # Return unfiltered if date parsing fails
  end

  def transaction_response_data(transaction)
    {
      id: transaction.id,
      amount: transaction.amount,
      amount_display: transaction.amount_display,
      formatted_amount: transaction.formatted_amount,
      description: transaction.description,
      merchant_name: transaction.merchant_name,
      date: transaction.date,
      currency: transaction.currency,
      pending: transaction.pending,
      is_expense: transaction.is_expense?,
      is_income: transaction.is_income?,
      plaid_transaction_id: transaction.plaid_transaction_id,
      account: {
        id: transaction.account.id,
        name: transaction.account.name,
        display_name: transaction.account.display_name,
        account_type: transaction.account.account_type
      },
      primary_category: transaction.primary_category ? {
        id: transaction.primary_category.id,
        name: transaction.primary_category.name,
        color: transaction.primary_category.color,
        full_name: transaction.primary_category.full_name
      } : nil,
      created_at: transaction.created_at,
      updated_at: transaction.updated_at
    }
  end

  def transaction_detail_data(transaction)
    data = transaction_response_data(transaction)

    # Add detailed classification information
    classifications = transaction.transaction_classifications.includes(:category).map do |classification|
      {
        id: classification.id,
        category: {
          id: classification.category.id,
          name: classification.category.name,
          color: classification.category.color,
          full_name: classification.category.full_name
        },
        confidence_score: classification.confidence_score,
        confidence_percentage: classification.confidence_percentage,
        auto_classified: classification.auto_classified,
        created_at: classification.created_at
      }
    end

    data[:classifications] = classifications
    data
  end

  def transactions_summary
    transactions = current_user.transactions

    # Apply same filters for summary
    transactions = apply_filters(transactions)

    {
      total_count: transactions.count,
      total_expenses: transactions.expenses.sum(:amount),
      total_income: transactions.income.sum(:amount),
      net_amount: transactions.sum(:amount),
      pending_count: transactions.pending.count,
      uncategorized_count: current_user.transactions
                                      .left_joins(:transaction_classifications)
                                      .where(transaction_classifications: { id: nil })
                                      .count
    }
  end

  def sync_account_transactions(account)
    # TODO: Implement actual Plaid sync logic here
    # For now, just update the last_sync_at timestamp
    account.update!(last_sync_at: Time.current)

    # In a real implementation, this would:
    # 1. Call Plaid API to get new transactions
    # 2. Create/update Transaction records
    # 3. Auto-classify new transactions
    # 4. Update account balances
  end
end
