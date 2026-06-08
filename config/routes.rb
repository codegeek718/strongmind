Rails.application.routes.draw do
  get "up", to: "health#show"
  get "/", to: "health#show"

  namespace :api do
    get "stats", to: "stats#show"
    resources :push_events, only: %i[index show], param: :github_event_id
    resources :actors, only: %i[index show], param: :github_id
    resources :repositories, only: %i[index show], param: :github_id
  end

  begin
    require "sidekiq/web"
    mount Sidekiq::Web => "/sidekiq"
  rescue LoadError, StandardError => e
    Rails.logger.warn("Sidekiq::Web not mounted: #{e.class}: #{e.message}")
  end
end
