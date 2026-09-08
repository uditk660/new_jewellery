JewelryApp - Rails 5 MVC skeleton

This is a minimal Rails 5-compatible skeleton for a jewelry catalog app. It's intended for Ruby 2.7.8 and Rails 5.0.7.2.

Setup

1. cd into the project

   ```bash
   cd /Users/apple/Documents/test_jewels/jewelry_app
   ```

2. Install gems

   ```bash
   bundle install
   ```

3. Create the database and run migrations

   ```bash
   bundle exec rake db:create db:migrate db:seed
   ```

4. Start the server

   ```bash
   bundle exec rails server
   ```

Notes
- This is a scaffolded skeleton to get you started. For production apps, switch to PostgreSQL and add authentication, authorization, admin UI, and image uploads.
- Tests are minimal. Expand with Rails' built-in test helpers and fixtures.
# new_jewellery
