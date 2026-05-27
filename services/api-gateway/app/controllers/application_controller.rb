class ApplicationController < ActionController::API
  # These URLs use Kubernetes internal DNS
  # Format: http://SERVICE-NAME.NAMESPACE.svc.cluster.local:PORT
  # This only works inside the cluster — external traffic cannot use these
  ANALYSIS_SERVICE = ENV.fetch('ANALYSIS_SERVICE_URL',
    'http://analysis-service-service.stockai.svc.cluster.local:3000')

  protected

  # Forward POST requests with the raw body intact
  def proxy_post(base_url, path)
    response = HTTParty.post(
      "#{base_url}#{path}",
      body:    request.raw_post,
      headers: {
        'Content-Type' => request.content_type,
        'X-Request-ID' => request.request_id
      }.compact,
      timeout: 60   # AI analysis can take up to 60 seconds
    )
    render json: JSON.parse(response.body), status: response.code
  rescue Net::ReadTimeout
    render json: { error: 'Analysis timed out. Try again.' }, status: :gateway_timeout
  rescue => e
    render json: { error: "Service unavailable: #{e.message}" }, status: :service_unavailable
  end

  def proxy_get(base_url, path)
    response = HTTParty.get("#{base_url}#{path}", timeout: 15)
    render json: JSON.parse(response.body), status: response.code
  rescue => e
    render json: { error: e.message }, status: :service_unavailable
  end
end
