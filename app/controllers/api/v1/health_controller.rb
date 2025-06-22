class Api::V1::HealthController < ApplicationController
  skip_before_action :authenticate_user!

  def index
    render json: {
      status: "ok",
      message: "API is healthy",
      timestamp: Time.current
    }
  end
end
