module Staff
  class SignupsController < BaseController
    def index
      @signups = User.order(created_at: :desc)
    end
  end
end
