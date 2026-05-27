class GatewayController < ApplicationController
  # POST /api/v1/analyze → forwards to analysis-service
  def analyze
    proxy_post(ANALYSIS_SERVICE, '/api/v1/analyze')
  end
end
