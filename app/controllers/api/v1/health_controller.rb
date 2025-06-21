class Api::V1::HealthController < ApplicationController
  def index
    render json: {
      status: "OK",
      timestamp: Time.current.iso8601,
      version: "1.0.0",
      environment: Rails.env
    }
  end
end
