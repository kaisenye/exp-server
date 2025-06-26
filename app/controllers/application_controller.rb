class ApplicationController < ActionController::API
  # Include Devise helpers for JWT authentication
  include ActionController::HttpAuthentication::Token::ControllerMethods

  # Set up authentication callback
  before_action :authenticate_user!

  # Handle common exceptions
  rescue_from ActiveRecord::RecordNotFound, with: :not_found
  rescue_from ActiveRecord::RecordInvalid, with: :unprocessable_entity
  rescue_from JWT::DecodeError, with: :unauthorized

  protected

  def authenticate_user!
    token = extract_token_from_header
    return unauthorized unless token

    begin
      jwt_payload = JWT.decode(token, jwt_secret, true, { algorithm: "HS256" }).first

      # Check if token is in denylist
      if JwtDenylist.exists?(jti: jwt_payload["jti"])
        return unauthorized
      end

      @current_user = User.find(jwt_payload["sub"])
    rescue JWT::ExpiredSignature
      render json: { error: "Token has expired" }, status: :unauthorized
    rescue JWT::DecodeError, ActiveRecord::RecordNotFound => e
      # Handle case where token was created with an invalid/short key
      if e.message.include?("key must be 32 bytes or longer")
        render json: { error: "Invalid token - please login again" }, status: :unauthorized
      else
        unauthorized
      end
    rescue StandardError => e
      # Catch any other JWT-related errors (including key length issues)
      if e.message.include?("key must be 32 bytes or longer")
        render json: { error: "Invalid token - please login again" }, status: :unauthorized
      else
        Rails.logger.error "JWT authentication error: #{e.message}"
        unauthorized
      end
    end
  end

  def current_user
    @current_user
  end

  private

  def extract_token_from_header
    auth_header = request.headers["Authorization"]
    return nil unless auth_header&.start_with?("Bearer ")

    auth_header.split(" ").last
  end

  def jwt_secret
    ENV["DEVISE_JWT_SECRET_KEY"] || Rails.application.credentials.devise_jwt_secret_key || Rails.application.secret_key_base
  end

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
