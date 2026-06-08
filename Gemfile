source "https://rubygems.org"

ruby "3.3.5"

gem "rails", "~> 7.1.3"
gem "pg", "~> 1.5"
gem "puma", "~> 6.4"

gem "sidekiq", "~> 7.2"
gem "redis", "~> 5.0"

gem "faraday", "~> 2.9"

gem "bootsnap", "~> 1.18", require: false

group :development, :test do
  gem "rspec-rails", "~> 6.1"
  gem "webmock", "~> 3.23"
  gem "factory_bot_rails", "~> 6.4"
  gem "debug", platforms: %i[mri], require: false
end
