class ProfitLossesController < ApplicationController
  def index
    @book = ProfitLoss.for(params, returns: session[:return_records])
    @house_name = house_name
    @metals = Metal.ordered
  end

  def new
    @metals = Metal.ordered
    @window = ProfitLoss::WINDOWS.include?(params[:window].to_s) ? params[:window].to_s : 'month'
    @from, @to = ProfitLoss.range_for(@window, params)
    @metal_id = params[:metal_id].presence
  end

  private

  def house_name
    current_user.try(:shop_profile).try(:shop_name).presence ||
      current_user.try(:shop_name).presence ||
      current_user.try(:display_name).presence ||
      'The house'
  end
end
