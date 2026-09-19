class HomeController < ApplicationController
  def dashboard
    unless user_signed_in?
      render 'pages/home', layout: 'marketing'
      return
    end

    today = Time.zone.today
    @house_name = house_name
    @now = Time.zone.now
    @report = HouseReport.for({ window: 'today' }, returns: session[:return_records], house_name: @house_name)
    @week = ProfitLoss.for({ window: 'week' })
    @month = ProfitLoss.for({ window: 'month' })
    @seven = ProfitLoss.for({ window: 'custom', from: today - 6, to: today })
    @series = @seven.series(:total)
    @series_max = @seven.series_max(:total)
    @latest = Order.includes(:customer, line_items: { jewelry_item: [:metal, :purity] })
                   .where.not(status: %w[cancelled failed])
                   .order(sale_date: :desc, id: :desc)
                   .limit(8)
  end

  private

  def house_name
    current_user.try(:shop_profile).try(:shop_name).presence ||
      current_user.try(:shop_name).presence ||
      current_user.try(:display_name).presence ||
      'The house'
  end
end
