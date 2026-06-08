class HealthController < ApplicationController
  def show
    ActiveRecord::Base.connection.execute("SELECT 1")
    render json: { status: "ok", time: Time.current.iso8601 }
  rescue => e
    render json: { status: "degraded", error: e.message }, status: :service_unavailable
  end
end
