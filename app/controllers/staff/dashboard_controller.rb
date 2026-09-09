module Staff
  class DashboardController < BaseController
    def show
      @pending_count = Subscription.pending.count
      @active_count = Subscription.where(status: 'active').where('ends_at >= ?', Time.current).count
      @suspended_count = Subscription.suspended.count
      @expiring_soon = Subscription.where(status: 'active').where('ends_at <= ? AND ends_at >= ?', 30.days.from_now, Time.current).order(:ends_at).limit(6)
      @recent_requests = Subscription.pending.includes(:user, :plan).order(created_at: :desc).limit(8)
      @recent_logs = AuditLog.newest.includes(:employee, :user, :plan).limit(8)
    end
  end
end
