module Staff
  class LogsController < BaseController
    def index
      @logs = AuditLog.newest.includes(:employee, :user, :plan, :subscription)
      @logs = @logs.where(action: params[:action_filter]) if params[:action_filter].present?
    end
  end
end
