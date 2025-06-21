class ApplicationController < ActionController::API
  # Include common API functionality
  include ActionController::HttpAuthentication::Token::ControllerMethods

  # Handle common exceptions
  rescue_from ActiveRecord::RecordNotFound, with: :not_found
  rescue_from ActiveRecord::RecordInvalid, with: :unprocessable_entity

  private

  def not_found(exception)
    render json: { error: exception.message }, status: :not_found
  end

  def unprocessable_entity(exception)
    render json: { error: exception.message }, status: :unprocessable_entity
  end

  def unauthorized
    render json: { error: "Unauthorized" }, status: :unauthorized
  end
end
