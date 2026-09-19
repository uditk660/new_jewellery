class SecurityController < ApplicationController
  def index
    load_gate
  end

  def new
    load_gate
  end

  private

  def load_gate
    sub = current_user.try(:active_subscription) || current_user.try(:current_subscription)
    @plan_name = sub&.plan&.name
    @house_name = current_user.try(:display_name).presence || 'This house'
    @strucxil_mail = 'hello@strucxil.com'
  end
end
