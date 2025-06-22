class Api::V1::CategoriesController < Api::V1::BaseController
  before_action :set_category, only: [ :show, :update, :destroy ]

  # GET /api/v1/categories
  def index
    @categories = current_user.categories.includes(:parent_category, :subcategories, :transactions)

    # Filter by parent/child hierarchy
    case params[:hierarchy]
    when "top_level"
      @categories = @categories.top_level
    when "children_only"
      @categories = @categories.where.not(parent_id: nil)
      # Default: return all categories
    end

    # Filter by budget status
    if params[:with_budget] == "true"
      @categories = @categories.with_budget
    end

    # Sort options
    case params[:sort]
    when "name"
      @categories = @categories.order(:name)
    when "spending"
      # Sort by current month spending (most spent first)
      @categories = @categories.left_joins(:transactions)
                               .where(transactions: { date: Date.current.beginning_of_month..Date.current.end_of_month })
                               .group("categories.id")
                               .order("SUM(CASE WHEN transactions.amount < 0 THEN ABS(transactions.amount) ELSE 0 END) DESC")
    when "budget_usage"
      @categories = @categories.with_budget.order(:budget_limit)
    else
      @categories = @categories.order(:name) # Default sort
    end

    categories_data = @categories.map do |category|
      category_response_data(category)
    end

    render json: {
      categories: categories_data,
      summary: categories_summary,
      hierarchy: {
        total_categories: current_user.categories.count,
        top_level_count: current_user.categories.top_level.count,
        with_budget_count: current_user.categories.with_budget.count
      }
    }
  end

  # GET /api/v1/categories/:id
  def show
    render json: {
      category: category_detail_data(@category)
    }
  end

  # POST /api/v1/categories
  def create
    @category = current_user.categories.build(category_params)

    if @category.save
      render json: {
        message: "Category created successfully",
        category: category_response_data(@category)
      }, status: :created
    else
      render json: {
        error: "Failed to create category",
        details: @category.errors.full_messages
      }, status: :unprocessable_entity
    end
  end

  # PUT /api/v1/categories/:id
  def update
    if @category.update(category_params)
      render json: {
        message: "Category updated successfully",
        category: category_response_data(@category)
      }
    else
      render json: {
        error: "Failed to update category",
        details: @category.errors.full_messages
      }, status: :unprocessable_entity
    end
  end

  # DELETE /api/v1/categories/:id
  def destroy
    # Check if category has transactions
    if @category.transactions.any?
      return render json: {
        error: "Cannot delete category with existing transactions",
        transaction_count: @category.transactions.count,
        suggestion: "Consider renaming or merging transactions to another category first"
      }, status: :unprocessable_entity
    end

    # Check if category has children
    if @category.has_children?
      return render json: {
        error: "Cannot delete category with subcategories",
        children_count: @category.subcategories.count,
        children: @category.subcategories.pluck(:name),
        suggestion: "Delete or move subcategories first"
      }, status: :unprocessable_entity
    end

    if @category.destroy
      render json: {
        message: "Category deleted successfully"
      }
    else
      render json: {
        error: "Failed to delete category"
      }, status: :unprocessable_entity
    end
  end

  # GET /api/v1/categories/budget_overview
  def budget_overview
    categories_with_budgets = current_user.categories.with_budget.includes(:transactions)

    budget_data = categories_with_budgets.map do |category|
      spent = category.total_spent_this_month
      remaining = category.budget_remaining
      percentage = category.budget_percentage_used

      {
        id: category.id,
        name: category.name,
        full_name: category.full_name,
        color: category.color,
        budget_limit: category.budget_limit,
        spent_this_month: spent,
        budget_remaining: remaining,
        percentage_used: percentage,
        over_budget: category.over_budget?,
        status: get_budget_status(percentage)
      }
    end

    # Calculate totals
    total_budget = categories_with_budgets.sum(:budget_limit) || 0
    total_spent = categories_with_budgets.sum(&:total_spent_this_month)
    total_remaining = total_budget - total_spent

    render json: {
      budget_overview: budget_data,
      summary: {
        total_budget: total_budget,
        total_spent: total_spent,
        total_remaining: total_remaining,
        overall_percentage: total_budget > 0 ? ((total_spent / total_budget) * 100).round(1) : 0,
        categories_over_budget: budget_data.count { |cat| cat[:over_budget] }
      },
      month: Date.current.strftime("%B %Y")
    }
  end

  # GET /api/v1/categories/spending_analysis
  def spending_analysis
    start_date = params[:start_date]&.to_date || Date.current.beginning_of_month
    end_date = params[:end_date]&.to_date || Date.current.end_of_month

    categories = current_user.categories.includes(:transactions)

    spending_data = categories.map do |category|
      transactions_in_period = category.transactions
                                      .joins(:account)
                                      .where(accounts: { user_id: current_user.id })
                                      .by_date_range(start_date, end_date)

      expense_amount = transactions_in_period.expenses.sum(:amount).abs
      income_amount = transactions_in_period.income.sum(:amount)
      transaction_count = transactions_in_period.count

      next if expense_amount.zero? && income_amount.zero?

      {
        id: category.id,
        name: category.name,
        full_name: category.full_name,
        color: category.color,
        expense_amount: expense_amount,
        income_amount: income_amount,
        net_amount: income_amount - expense_amount,
        transaction_count: transaction_count,
        average_transaction: transaction_count > 0 ? (expense_amount + income_amount) / transaction_count : 0,
        has_budget: category.budget_limit.present?,
        budget_limit: category.budget_limit
      }
    end.compact

    # Sort by total expense amount (highest first)
    spending_data.sort_by! { |cat| -cat[:expense_amount] }

    total_expenses = spending_data.sum { |cat| cat[:expense_amount] }
    total_income = spending_data.sum { |cat| cat[:income_amount] }

    render json: {
      spending_analysis: spending_data,
      period: {
        start_date: start_date,
        end_date: end_date,
        days: (end_date - start_date).to_i + 1
      },
      summary: {
        total_expenses: total_expenses,
        total_income: total_income,
        net_amount: total_income - total_expenses,
        categories_with_spending: spending_data.count,
        top_category: spending_data.first
      }
    }
  end

  private

  def set_category
    @category = current_user.categories.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render json: {
      error: "Category not found"
    }, status: :not_found
  end

  def category_params
    params.require(:category).permit(
      :name,
      :description,
      :color,
      :parent_id,
      :budget_limit
    )
  end

  def category_response_data(category)
    {
      id: category.id,
      name: category.name,
      description: category.description,
      color: category.color,
      full_name: category.full_name,
      parent_id: category.parent_id,
      parent: category.parent_category ? {
        id: category.parent_category.id,
        name: category.parent_category.name,
        color: category.parent_category.color
      } : nil,
      children_count: category.subcategories.count,
      has_children: category.has_children?,
      budget_limit: category.budget_limit,
      total_spent_this_month: category.total_spent_this_month,
      budget_remaining: category.budget_remaining,
      budget_percentage_used: category.budget_percentage_used,
      over_budget: category.over_budget?
    }
  end

  def category_detail_data(category)
    data = category_response_data(category)

    # Add children information
    if category.has_children?
      data[:children] = category.subcategories.map do |child|
        {
          id: child.id,
          name: child.name,
          color: child.color,
          transaction_count: child.transactions.count,
          spent_this_month: child.total_spent_this_month
        }
      end
    end

    # Add recent transactions
    data[:recent_transactions] = category.transactions
                                        .joins(:account)
                                        .where(accounts: { user_id: current_user.id })
                                        .recent
                                        .limit(10)
                                        .map do |transaction|
      {
        id: transaction.id,
        amount: transaction.amount,
        formatted_amount: transaction.formatted_amount,
        description: transaction.description,
        date: transaction.date,
        account_name: transaction.account.name
      }
    end

    data
  end

  def categories_summary
    categories = current_user.categories
    total_budget = categories.with_budget.sum(:budget_limit) || 0
    total_spent = categories.sum(&:total_spent_this_month)

    {
      total_categories: categories.count,
      top_level_categories: categories.top_level.count,
      categories_with_budgets: categories.with_budget.count,
      total_budget_allocated: total_budget,
      total_spent_this_month: total_spent,
      budget_utilization: total_budget > 0 ? ((total_spent / total_budget) * 100).round(1) : 0
    }
  end

  def get_budget_status(percentage)
    case percentage
    when 0...50
      "low"
    when 50...80
      "moderate"
    when 80...100
      "high"
    else
      "over_budget"
    end
  end
end
