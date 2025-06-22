class Api::V1::Auth::SessionsController < ApplicationController
  skip_before_action :authenticate_user!, only: [ :create ]

  def create
    user = User.find_by(email: params[:email])

    if user&.valid_password?(params[:password])
      token = generate_jwt_token(user)
      render json: {
        message: "Login successful",
        token: token,
        user: user_data(user)
      }, status: :ok
    else
      render json: {
        error: "Invalid email or password"
      }, status: :unauthorized
    end
  end

  def destroy
    if current_user
      # Add token to denylist
      revoke_jwt_token
      render json: {
        message: "Logged out successfully"
      }, status: :ok
    else
      render json: {
        error: "No active session found"
      }, status: :unauthorized
    end
  end

  private

  def user_data(user)
    {
      id: user.id,
      email: user.email,
      first_name: user.first_name,
      last_name: user.last_name,
      created_at: user.created_at
    }
  end

  def generate_jwt_token(user)
    payload = {
      sub: user.id,
      exp: 1.day.from_now.to_i,
      iat: Time.current.to_i,
      jti: SecureRandom.uuid
    }

    JWT.encode(payload, jwt_secret, "HS256")
  end

  def revoke_jwt_token
    token = extract_token_from_header
    return unless token

    begin
      payload = JWT.decode(token, jwt_secret, true, { algorithm: "HS256" }).first
      JwtDenylist.create!(jti: payload["jti"], exp: Time.at(payload["exp"]))
    rescue JWT::DecodeError
      # Token already invalid
    end
  end

  def jwt_secret
    ENV["DEVISE_JWT_SECRET_KEY"] || Rails.application.secret_key_base
  end
end
