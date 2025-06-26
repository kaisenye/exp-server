class Api::V1::DashboardController < Api::V1::BaseController
  def stats
    begin
      # Get user's account and transaction statistics
      Rails.logger.info "Fetching dashboard stats for user: #{current_user.id}"

      accounts = current_user.accounts.active
      Rails.logger.info "Found #{accounts.count} active accounts"

      total_balance = accounts.sum(:balance_current)
      Rails.logger.info "Calculated total balance: #{total_balance}"

      # Get recent transactions count
      recent_transactions = current_user.transactions.where("transactions.created_at > ?", 30.days.ago).count
      Rails.logger.info "Found #{recent_transactions} recent transactions"

      # Get account count by type
      account_types = accounts.group(:account_type).count
      Rails.logger.info "Account types: #{account_types}"

      render json: {
        total_balance: total_balance,
        total_accounts: accounts.count,
        recent_transactions: recent_transactions,
        account_types: account_types,
        plaid_linked: accounts.where.not(plaid_access_token: [ nil, "" ]).count > 0
      }
    rescue => e
      Rails.logger.error "Error fetching dashboard stats: #{e.message}"
      Rails.logger.error "Backtrace: #{e.backtrace.join("\n")}"
      render json: {
        error: "Failed to fetch dashboard statistics",
        details: e.message
      }, status: :internal_server_error
    end
  end
end
