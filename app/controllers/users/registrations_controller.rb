module Users
  class RegistrationsController < Devise::RegistrationsController
    before_action :configure_sign_up_params, only: [:create]

    def create
      super do |user|
        next unless user.persisted?

        AuditLog.record!(
          employee: nil,
          action: 'signed_up',
          user: user,
          notes: [user.shop_name.presence, user.email, user.phone.presence].compact.join(' · '),
          ip: user.sign_up_ip
        )
      rescue StandardError => e
        Rails.logger.error("Signup trail failed for user #{user.id}: #{e.class}: #{e.message}")
      end
    end

    protected

    def build_resource(hash = {})
      super
      resource.sign_up_ip = request.remote_ip
    end

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
