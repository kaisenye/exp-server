class Insight < ApplicationRecord
  belongs_to :user

  validates :title, :insight_type, presence: true
  validates :insight_type, inclusion: {
    in: %w[spending_trend budget_alert category_analysis monthly_summary yearly_comparison unusual_activity]
  }

  scope :by_type, ->(type) { where(insight_type: type) }
  scope :recent, -> { order(created_at: :desc) }
  scope :for_period, ->(period) { where(created_for_period: period) }

  def self.generate_monthly_insights(user)
    current_month = Date.current.strftime("%Y-%m")

    user.insights.for_period(current_month).destroy_all

    generate_spending_trend(user, current_month)

    generate_budget_alerts(user, current_month)

    generate_category_analysis(user, current_month)
  end

  private

  def self.generate_spending_trend(user, period)
    start_date = Date.current.beginning_of_month
    end_date = Date.current.end_of_month

    current_spending = user.transactions
                          .joins(:account)
                          .by_date_range(start_date, end_date)
                          .expenses
                          .sum(:amount)
                          .abs

    last_month_start = 1.month.ago.beginning_of_month
    last_month_end = 1.month.ago.end_of_month

    last_month_spending = user.transactions
                             .joins(:account)
                             .by_date_range(last_month_start, last_month_end)
                             .expenses
                             .sum(:amount)
                             .abs

    if last_month_spending > 0
      percentage_change = ((current_spending - last_month_spending) / last_month_spending * 100).round
      trend = percentage_change > 0 ? "increased" : "decreased"

      user.insights.create!(
        title: "Monthly Spending Trend",
        description: "Your spending has #{trend} by #{percentage_change.abs}% compared to last month",
        insight_type: "spending_trend",
        created_for_period: period,
        data: {
          current_month_spending: current_spending,
          last_month_spending: last_month_spending,
          percentage_change: percentage_change
        }
      )
    end
  end

  def self.generate_budget_alerts(user, period)
    user.categories.with_budget.each do |category|
      if category.over_budget?
        user.insights.create!(
          title: "Budget Alert: #{category.name}",
          description: "You've exceeded your budget for #{category.name} by $#{(category.total_spent_this_month - category.budget_limit).round(2)}",
          insight_type: "budget_alert",
          created_for_period: period,
          data: {
            category_id: category.id,
            budget_limit: category.budget_limit,
            amount_spent: category.total_spent_this_month,
            overage: category.total_spent_this_month - category.budget_limit
          }
        )
      end
    end
  end

  def self.generate_category_analysis(user, period)
    start_date = Date.current.beginning_of_month
    end_date = Date.current.end_of_month

    category_spending = user.categories.joins(:transactions)
                           .where(transactions: { date: start_date..end_date })
                           .where("transactions.amount < 0")
                           .group("categories.name")
                           .sum("transactions.amount")
                           .transform_values(&:abs)

    if category_spending.any?
      top_category = category_spending.max_by { |_, amount| amount }

      user.insights.create!(
        title: "Top Spending Category",
        description: "Your highest spending category this month is #{top_category[0]} with $#{top_category[1].round(2)}",
        insight_type: "category_analysis",
        created_for_period: period,
        data: {
          top_category: top_category[0],
          amount: top_category[1],
          all_categories: category_spending
        }
      )
    end
  end
end
