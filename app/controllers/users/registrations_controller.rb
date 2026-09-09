module Users
  class RegistrationsController < Devise::RegistrationsController
    before_action :configure_sign_up_params, only: [:create]

    protected

    def after_sign_up_path_for(_resource)
      new_subscription_path
    end

    def after_inactive_sign_up_path_for(_resource)
      new_subscription_path
    end

    def configure_sign_up_params
      devise_parameter_sanitizer.permit(:sign_up, keys: [:shop_name, :full_name, :phone])
    end
  end
end
