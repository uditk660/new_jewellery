module Staff
  class EarningsController < BaseController
    def show
      @report = LicenceEarnings.new(month: params[:month])
    end
  end
end
