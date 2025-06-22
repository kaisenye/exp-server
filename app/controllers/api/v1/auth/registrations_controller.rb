class Api::V1::Auth::RegistrationsController < ApplicationController
  skip_before_action :authenticate_user!, only: [ :create ]

  def create
    user = User.new(user_params)

    if user.save
      token = generate_jwt_token(user)
      render json: {
        message: "Registration successful",
        token: token,
        user: user_data(user)
      }, status: :created
    else
      render json: {
        error: "Registration failed",
        details: user.errors.full_messages
      }, status: :unprocessable_entity
    end
  end

  private

  def user_params
    params.require(:user).permit(:email, :password, :password_confirmation, :first_name, :last_name)
  end

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

  def jwt_secret
    ENV["DEVISE_JWT_SECRET_KEY"] || Rails.application.secret_key_base
  end
end
