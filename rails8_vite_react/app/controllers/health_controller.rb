class HealthController < ApplicationController
  skip_before_action :verify_authenticity_token
  
  def check
    render json: { 
      status: 'ok', 
      timestamp: Time.current,
      version: '1.0.0'
    }
  end
end
