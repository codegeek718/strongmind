require "active_support/core_ext/integer/time"

Rails.application.configure do
  config.cache_classes = false
  config.eager_load = false
  config.consider_all_requests_local = true

  config.active_support.deprecation = :log
  config.active_support.disallowed_deprecation = :raise
  config.active_support.disallowed_deprecation_warnings = []

  config.action_controller.raise_on_missing_callback_actions = true

  config.active_record.migration_error = :page_load
  config.active_record.verbose_query_logs = true

  config.logger = ActiveSupport::Logger.new($stdout)
  config.log_level = ENV.fetch("LOG_LEVEL", "debug")
end
