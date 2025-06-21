# 💰 Expense Tracker Backend

A Ruby on Rails API-only backend for personal expense tracking with Plaid integration, JWT authentication, and intelligent categorization.

## 🚀 Features

- **JWT Authentication** with Devise
- **Bank Account Integration** via Plaid API
- **Automatic Transaction Categorization** with confidence scoring
- **Hierarchical Expense Categories** with budget tracking
- **Financial Insights** and analytics
- **PostgreSQL** for production, SQLite for testing
- **Background Jobs** with Sidekiq
- **Comprehensive API** with JSON serialization

## 🛠 Tech Stack

- **Ruby on Rails 8.0.2** (API-only)
- **PostgreSQL** (production/development)
- **SQLite3** (testing)
- **JWT** authentication
- **Plaid** for bank integration
- **Sidekiq** for background jobs
- **RSpec** for testing

## 📋 Quick Start

### Prerequisites

- Ruby 3.2+
- PostgreSQL 14+
- Redis (for background jobs)

### Installation

1. **Clone the repository**
   ```bash
   git clone https://github.com/yourusername/exp-server.git
   cd exp-server
   ```

2. **Install dependencies**
   ```bash
   bundle install
   ```

3. **Setup database**
   ```bash
   bin/rails db:create
   bin/rails db:migrate
   bin/rails db:seed
   ```

4. **Start the server**
   ```bash
   bin/rails server
   ```

### Environment Variables

Create a `.env` file with:

```bash
# Database
DATABASE_USER=postgres
DATABASE_PASSWORD=
DATABASE_HOST=localhost
DATABASE_PORT=5432

# Plaid API
PLAID_CLIENT_ID=your_plaid_client_id
PLAID_SECRET=your_plaid_secret
PLAID_ENV=sandbox

# Security
DEVISE_JWT_SECRET_KEY=your_jwt_secret_key
ENCRYPTION_KEY=your_32_character_encryption_key

# Background Jobs
REDIS_URL=redis://localhost:6379/0
```

## 📊 Database Schema

```
Users (1) ──→ (many) Accounts (1) ──→ (many) Transactions
  │                                              │
  │                                              │
  ├──→ (many) Categories                         │
  │             │                                │
  │             └──→ (many) TransactionClassifications ←─┘
  │
  └──→ (many) Insights
```

## 🔗 API Endpoints (Planned)

### Authentication
- `POST /auth/login` - User login
- `POST /auth/register` - User registration
- `DELETE /auth/logout` - Logout

### Accounts
- `GET /api/v1/accounts` - List accounts
- `POST /api/v1/accounts` - Link new account
- `PUT /api/v1/accounts/:id` - Update account

### Transactions
- `GET /api/v1/transactions` - List transactions
- `POST /api/v1/transactions/sync` - Sync from Plaid
- `PUT /api/v1/transactions/:id/categorize` - Categorize

### Categories
- `GET /api/v1/categories` - List categories
- `POST /api/v1/categories` - Create category
- `PUT /api/v1/categories/:id` - Update category

## 💾 Sample Data

The seed file includes:
- Demo user: `demo@example.com` / `password123`
- 50 pre-defined categories
- 3 sample bank accounts
- 7 sample transactions with classifications

## 🧪 Testing

```bash
# Run all tests
bundle exec rspec

# Run specific test file
bundle exec rspec spec/models/user_spec.rb
```

## 🚀 Deployment

### Render (Recommended)

1. Connect your GitHub repository to Render
2. Set environment variables in Render dashboard
3. Deploy with automatic migrations

### Environment Variables for Production

```bash
DATABASE_NAME=your_render_db_name
DATABASE_USERNAME=your_render_db_user
DATABASE_PASSWORD=your_render_db_password
DATABASE_HOST=your_render_db_host
DATABASE_PORT=5432
```

## 📈 Current Status

✅ **Completed:**
- Database models and relationships
- JWT authentication setup
- Sample data and seed files
- Basic validations and scopes

🚧 **In Progress:**
- API controllers and routes
- Plaid integration
- Background job setup

📋 **Todo:**
- API documentation
- Production deployment
- Frontend integration

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 📞 Support

For questions or support, please open an issue on GitHub.

---

**Note:** This is an active development project. Check `PROJECT_STATUS.md` for detailed development status and next steps.
