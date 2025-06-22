class Api::V1::Auth::UsersController < ApplicationController
  def show
    render json: {
      user: user_data(@current_user)
    }
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
end
