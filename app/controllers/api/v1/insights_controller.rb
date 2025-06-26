class Api::V1::InsightsController < Api::V1::BaseController
  # GET /api/v1/insights
  def index
    @insights = current_user.insights.includes(:user)

    # Filter by insight type if specified
    if params[:type].present?
      @insights = @insights.by_type(params[:type])
    end

    # Filter by period if specified
    if params[:period].present?
      @insights = @insights.for_period(params[:period])
    end

    # Sort by most recent first
    @insights = @insights.recent

    # Pagination
    page = params[:page]&.to_i || 1
    per_page = params[:per_page]&.to_i || 20
    per_page = [ per_page, 50 ].min # Max 50 per page

    @insights = @insights.offset((page - 1) * per_page).limit(per_page)

    insights_data = @insights.map do |insight|
      insight_response_data(insight)
    end

    # Get total count for pagination
    total_count = current_user.insights.count
    total_pages = (total_count.to_f / per_page).ceil

    render json: {
      insights: insights_data,
      pagination: {
        current_page: page,
        per_page: per_page,
        total_count: total_count,
        total_pages: total_pages
      },
      summary: insights_summary,
      available_types: insight_types
    }
  end

  # GET /api/v1/insights/:id
  def show
    @insight = current_user.insights.find(params[:id])

    render json: {
      insight: insight_detail_data(@insight)
    }
  rescue ActiveRecord::RecordNotFound
    render json: {
      error: "Insight not found"
    }, status: :not_found
  end

  # POST /api/v1/insights/generate
  def generate
    period = params[:period] || Date.current.strftime("%Y-%m")
    force_regenerate = params[:force] == "true"

    # Check if insights already exist for this period
    existing_insights = current_user.insights.for_period(period)
    if existing_insights.any? && !force_regenerate
      return render json: {
        message: "Insights already exist for this period",
        period: period,
        existing_count: existing_insights.count,
        insights: existing_insights.map { |insight| insight_response_data(insight) },
        suggestion: "Use force=true parameter to regenerate"
      }
    end

    # Generate new insights
    begin
      Insight.generate_monthly_insights(current_user)

      # Get the newly generated insights
      new_insights = current_user.insights.for_period(period).recent

      render json: {
        message: "Insights generated successfully",
        period: period,
        generated_count: new_insights.count,
        insights: new_insights.map { |insight| insight_response_data(insight) }
      }
    rescue => e
      render json: {
        error: "Failed to generate insights",
        details: e.message
      }, status: :unprocessable_entity
    end
  end

  # DELETE /api/v1/insights/:id
  def destroy
    @insight = current_user.insights.find(params[:id])

    if @insight.destroy
      render json: {
        message: "Insight deleted successfully"
      }
    else
      render json: {
        error: "Failed to delete insight"
      }, status: :unprocessable_entity
    end
  rescue ActiveRecord::RecordNotFound
    render json: {
      error: "Insight not found"
    }, status: :not_found
  end

  # GET /api/v1/insights/types
  def types
    render json: {
      insight_types: insight_types_with_descriptions
    }
  end

  private

  def insight_response_data(insight)
    {
      id: insight.id,
      title: insight.title,
      description: insight.description,
      insight_type: insight.insight_type,
      created_for_period: insight.created_for_period,
      data: insight.data,
      created_at: insight.created_at,
      updated_at: insight.updated_at
    }
  end

  def insight_detail_data(insight)
    data = insight_response_data(insight)

    # Add additional context based on insight type
    case insight.insight_type
    when "budget_alert"
      if insight.data&.dig("category_id")
        category = current_user.categories.find_by(id: insight.data["category_id"])
        data[:category] = category ? {
          id: category.id,
          name: category.name,
          color: category.color,
          full_name: category.full_name
        } : nil
      end
    when "category_analysis"
      # Add current month comparison if available
      current_spending = current_user.categories
                                   .joins(:transactions)
                                   .where(transactions: { date: Date.current.beginning_of_month..Date.current.end_of_month })
                                   .where("transactions.amount < 0")
                                   .group("categories.name")
                                   .sum("transactions.amount")
                                   .transform_values(&:abs)
      data[:current_month_comparison] = current_spending
    end

    data
  end

  def insights_summary
    insights = current_user.insights
    current_month = Date.current.strftime("%Y-%m")

    {
      total_insights: insights.count,
      this_month_count: insights.for_period(current_month).count,
      by_type: insights.group(:insight_type).count,
      latest_generation: insights.maximum(:created_at),
      needs_generation: should_generate_insights?
    }
  end

  def insight_types
    %w[spending_trend budget_alert category_analysis monthly_summary yearly_comparison unusual_activity]
  end

  def insight_types_with_descriptions
    {
      "spending_trend" => "Track spending changes compared to previous periods",
      "budget_alert" => "Notifications when budgets are exceeded or approaching limits",
      "category_analysis" => "Analysis of spending patterns by category",
      "monthly_summary" => "Comprehensive monthly financial summary",
      "yearly_comparison" => "Year-over-year spending comparisons",
      "unusual_activity" => "Detection of unusual spending patterns or transactions"
    }
  end

  def should_generate_insights?
    current_month = Date.current.strftime("%Y-%m")
    current_user.insights.for_period(current_month).empty?
  end
end
