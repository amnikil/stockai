Rails.application.routes.draw do
  post '/api/v1/analyze', to: 'analysis#analyze'
  get  '/health',         to: proc { [200, {}, ['{"status":"ok"}']] }
end
