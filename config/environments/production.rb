require "active_support/core_ext/integer/time"

Rails.application.configure do
  config.cache_classes = true
  config.eager_load = true

  config.consider_all_requests_local = false

  config.logger = ActiveSupport::Logger.new($stdout)
  config.log_level = ENV.fetch("LOG_LEVEL", "info")
  config.log_tags = [:request_id]

  config.active_record.dump_schema_after_migration = false
end
