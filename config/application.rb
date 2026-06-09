require_relative "boot"

require "rails"
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "action_controller/railtie"

Bundler.require(*Rails.groups)

module GithubIngestor
  class Application < Rails::Application
    config.load_defaults 7.1
    config.api_only = true
    config.active_job.queue_adapter = :sidekiq
    config.time_zone = "UTC"

    # api_only drops sessions/cookies; add them back just for the Sidekiq dashboard.
    config.middleware.use ActionDispatch::Cookies
    config.middleware.use ActionDispatch::Session::CookieStore, key: "_github_ingestor_session"

    config.generators.system_tests = nil
  end
end
