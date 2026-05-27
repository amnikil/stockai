Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins '*'   # In production, change this to your actual frontend domain
    resource '*',
      headers: :any,
      methods: [:get, :post, :options],
      expose: ['Content-Type']
  end
end
