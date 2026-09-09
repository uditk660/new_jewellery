source 'https://rubygems.org'

ruby '3.1.0'

gem "rails", "~> 7.2.3"
# Rails 7.2 JSON encode/decode still passes `quirks_mode:`; json 2.10+ removed it.
gem "json", "~> 2.9.0"

# DB
gem 'mysql2', '>= 0.5.3'

# Asset pipeline (Rails 7 no longer depends on sprockets-rails)
gem 'sprockets-rails'
gem 'sass-rails', '>= 6'
gem 'uglifier', '>= 1.3.0'

# Use ActiveModel has_secure_password
gem 'bcrypt', '~> 3.1.7'
gem 'jbuilder', '~> 2.5'

# Use Puma as the app server
gem 'puma', '>= 5.0'

# Use CoffeeScript for .coffee assets and views
gem 'coffee-rails', '~> 4.2'

# Turbolinks
gem 'turbolinks', '~> 5'
gem 'jquery-rails'

# QR code generation for invoices
gem 'rqrcode'

# Authentication
gem 'devise', '~> 4.8'

group :development, :test do
  gem 'byebug'
end

group :development do
  gem 'listen', '~> 3.3'
  gem 'spring'
  gem 'spring-watcher-listen', '~> 2.0.0'
end

group :test do
  gem 'minitest'
end
