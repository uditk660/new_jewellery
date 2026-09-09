class ShopProfilesController < ApplicationController
  def show
    @profile = current_user.shop_profile
    redirect_to(shop_setup_path, alert: 'Complete showroom registration first.') and return unless @profile&.completed?
  end
end
