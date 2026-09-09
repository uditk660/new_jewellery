Devise.setup do |config|
  # Configure the e-mail address which will be shown in Devise::Mailer
  config.mailer_sender = ENV.fetch('MAILER_SENDER', 'please-change-me@example.com')

  # Use ActiveRecord ORM
  require 'devise/orm/active_record'

  # Use the application's secret_key_base if available (recommended)
  if Rails.application.respond_to?(:secret_key_base) && Rails.application.secret_key_base.present?
    config.secret_key = Rails.application.secret_key_base
  end

  config.scoped_views = true
end
