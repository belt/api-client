Rails.application.routes.draw do
  # Health check endpoint (Rails 8 convention)
  get "up" => "rails/health#show", :as => :rails_health_check
end
