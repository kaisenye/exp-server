class PlaidService
  include Singleton

  def initialize
    configure_plaid_client
  end

  def self.create_link_token(user_id, products: [ "transactions" ])
    instance.create_link_token(user_id, products)
  end

  def self.exchange_public_token(public_token)
    instance.exchange_public_token(public_token)
  end

  def self.fetch_accounts(access_token)
    instance.fetch_accounts(access_token)
  end

  def self.fetch_transactions(access_token, start_date, end_date)
    instance.fetch_transactions(access_token, start_date, end_date)
  end

  def self.fetch_recent_transactions(access_token, days: 30)
    end_date = Date.current
    start_date = end_date - days.days
    instance.fetch_transactions(access_token, start_date, end_date)
  end

  def self.remove_item(access_token)
    instance.remove_item(access_token)
  end

  def create_link_token(user_id, products = [ "transactions" ])
    client = get_client

    response = client.link_token.create(
      user: {
        client_user_id: user_id.to_s
      },
      client_name: "Expense Tracker",
      products: products,
      country_codes: [ "US" ],
      language: "en"
    )

    response["link_token"]
  rescue Plaid::PlaidAPIError => e
    Rails.logger.error "Plaid link token creation failed: #{e.message}"
    raise PlaidError, "Failed to create link token: #{e.message}"
  rescue => e
    Rails.logger.error "Unexpected error in create_link_token: #{e.message}"
    raise PlaidError, "Unexpected error during link token creation: #{e.message}"
  end

  def exchange_public_token(public_token)
    client = get_client

    response = client.item.public_token.exchange(public_token)

    {
      access_token: response["access_token"],
      item_id: response["item_id"]
    }
  rescue Plaid::PlaidAPIError => e
    Rails.logger.error "Plaid API error in exchange_public_token: #{e.message}"
    raise PlaidError, "Failed to exchange public token: #{e.message}"
  rescue => e
    Rails.logger.error "Unexpected error in exchange_public_token: #{e.message}"
    raise PlaidError, "Unexpected error during token exchange: #{e.message}"
  end

  def fetch_accounts(access_token)
    client = get_client
    response = client.accounts.get(access_token)

    response["accounts"].map do |account|
      {
        plaid_account_id: account["account_id"],
        name: account["name"],
        official_name: account["official_name"],
        institution_name: account["name"].split.first || "Unknown", # Simple extraction
        type: account["type"],
        subtype: account["subtype"],
        balance_current: account["balances"]["current"],
        balance_available: account["balances"]["available"],
        currency: account["balances"]["iso_currency_code"] || "USD"
      }
    end
  rescue Plaid::PlaidAPIError => e
    Rails.logger.error "Plaid accounts fetch failed: #{e.message}"
    raise PlaidError, "Failed to fetch accounts: #{e.message}"
  rescue => e
    Rails.logger.error "Unexpected error in fetch_accounts: #{e.message}"
    raise PlaidError, "Unexpected error during accounts fetch: #{e.message}"
  end

  def fetch_transactions(access_token, start_date, end_date)
    client = get_client

    response = client.transactions.get(
      access_token,
      start_date,
      end_date
    )

    transactions = response["transactions"]
    total_transactions = response["total_transactions"]

    # If there are more transactions, fetch them in batches
    if transactions.count < total_transactions
      offset = transactions.count
      while offset < total_transactions
        batch_response = client.transactions.get(
          access_token,
          start_date,
          end_date,
          offset: offset
        )
        transactions += batch_response["transactions"]
        offset += batch_response["transactions"].count

        # Safety break to avoid infinite loops
        break if batch_response["transactions"].empty?
      end
    end

    transactions.map do |transaction|
      {
        plaid_transaction_id: transaction["transaction_id"],
        plaid_account_id: transaction["account_id"],
        amount: -transaction["amount"], # Plaid amounts are positive for outgoing, we want negative
        currency: transaction["iso_currency_code"] || "USD",
        date: Date.parse(transaction["date"]),
        merchant_name: transaction["merchant_name"],
        description: transaction["name"],
        category: transaction["category"]&.first,
        subcategory: transaction["category"]&.second,
        pending: transaction["pending"]
      }
    end
  rescue Plaid::PlaidAPIError => e
    Rails.logger.error "Plaid transactions fetch failed: #{e.message}"
    raise PlaidError, "Failed to fetch transactions: #{e.message}"
  rescue => e
    Rails.logger.error "Unexpected error in fetch_transactions: #{e.message}"
    raise PlaidError, "Unexpected error during transactions fetch: #{e.message}"
  end

  def remove_item(access_token)
    client = get_client
    client.item.remove(access_token)
  rescue Plaid::PlaidAPIError => e
    Rails.logger.error "Plaid item removal failed: #{e.message}"
    raise PlaidError, "Failed to remove item: #{e.message}"
  rescue => e
    Rails.logger.error "Unexpected error in remove_item: #{e.message}"
    raise PlaidError, "Unexpected error during item removal: #{e.message}"
  end

  private

  def configure_plaid_client
    # Set environment variables if not already set (for testing)
    ENV["PLAID_CLIENT_ID"] ||= "test_client_id"
    ENV["PLAID_SECRET"] ||= "test_secret"
    ENV["PLAID_ENV"] ||= "sandbox"
  end

  def get_client
    @client ||= Plaid::Client.new(
      env: plaid_environment,
      client_id: ENV["PLAID_CLIENT_ID"],
      secret: ENV["PLAID_SECRET"]
    )
  rescue => e
    Rails.logger.error "Failed to create Plaid client: #{e.message}"
    raise PlaidError, "Failed to configure Plaid client: #{e.message}"
  end

  def plaid_environment
    case ENV["PLAID_ENV"]&.downcase
    when "production"
      :production
    when "development"
      :development
    else
      :sandbox
    end
  end
end

# Custom exception for Plaid-related errors
class PlaidError < StandardError
  def initialize(message)
    super(message)
  end
end
