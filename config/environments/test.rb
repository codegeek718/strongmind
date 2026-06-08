require "active_support/core_ext/integer/time"

Rails.application.configure do
  config.cache_classes = true
  config.eager_load = ENV["CI"].present?

  config.consider_all_requests_local = true
  config.action_dispatch.show_exceptions = :none
  config.active_support.deprecation = :stderr

  config.action_controller.raise_on_missing_callback_actions = true

  config.logger = ActiveSupport::Logger.new($stdout)
  config.log_level = ENV.fetch("LOG_LEVEL", "warn")

  config.active_job.queue_adapter = :test
end
