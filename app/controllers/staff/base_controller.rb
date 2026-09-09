module Staff
  class BaseController < ApplicationController
    skip_before_action :authenticate_user!
    skip_before_action :enforce_subscription!
    before_action :authenticate_employee!
    layout 'staff'

    helper_method :current_employee

    private

    def log_action!(action, user: nil, subscription: nil, plan: nil, notes: nil)
      AuditLog.record!(
        employee: current_employee,
        action: action,
        user: user || subscription&.user,
        subscription: subscription,
        plan: plan,
        notes: notes,
        ip: request.remote_ip
      )
    end
  end
end
