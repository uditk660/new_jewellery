class ApplicationController < ActionController::Base
  protect_from_forgery with: :exception
  before_action :authenticate_user!, unless: :skip_user_auth?
  before_action :enforce_subscription!, if: :user_signed_in?
  before_action :enforce_shop_setup!, if: :user_signed_in?
  layout :layout_by_resource

  helper_method :subscription_live?, :shop_setup_complete?

  private

  def skip_user_auth?
    devise_controller? || staff_controller?
  end

  def staff_controller?
    controller_path.start_with?('staff/')
  end

  def enforce_subscription!
    return if staff_controller? || devise_controller?
    return if controller_name == 'subscriptions' || controller_name == 'shop_setups'
    return if subscription_live?

    sub = current_user.current_subscription
    if sub && %w[pending suspended].include?(sub.effective_status)
      redirect_to pending_subscription_path
    else
      redirect_to new_subscription_path
    end
  end

  def enforce_shop_setup!
    return if staff_controller? || devise_controller?
    return if controller_name == 'shop_setups'
    return unless subscription_live?
    return if shop_setup_complete?

    redirect_to shop_setup_path
  end

  def shop_setup_complete?
    user_signed_in? && current_user.shop_setup_complete?
  end

  def subscription_live?
    user_signed_in? && current_user.subscription_live?
  end

  def layout_by_resource
    if staff_controller?
      'staff'
    elsif devise_controller? && try(:resource_name) == :employee
      'staff_auth'
    elsif devise_controller?
      'devise'
    else
      'application'
    end
  end

  def after_sign_in_path_for(resource)
    if resource.is_a?(Employee)
      staff_root_path
    elsif resource.subscription_live?
      resource.shop_setup_complete? ? root_path : shop_setup_path
    elsif resource.current_subscription && %w[pending suspended].include?(resource.current_subscription.effective_status)
      pending_subscription_path
    else
      new_subscription_path
    end
  end

  def after_sign_out_path_for(resource_or_scope)
    if resource_or_scope == :employee || resource_or_scope.is_a?(Employee)
      new_employee_session_path
    else
      new_user_session_path
    end
  end
end
