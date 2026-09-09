module Staff
  class SubscriptionRequestsController < BaseController
    def index
      @requests = Subscription.pending.includes(:user, :plan).order(created_at: :desc)
    end

    def show
      @subscription = Subscription.includes(:user, :plan, :reviewed_by).find(params[:id])
    end

    def approve
      subscription = Subscription.find(params[:id])
      note = params[:decision_note]
      subscription.approve!(current_employee, note: note)
      log_action!('approved', subscription: subscription, notes: note)
      redirect_to staff_subscription_requests_path, notice: "Approved #{subscription.user.display_name} — valid for 1 year."
    end

    def reject
      subscription = Subscription.find(params[:id])
      note = params[:decision_note].to_s.strip
      if note.blank?
        redirect_to staff_subscription_request_path(subscription), alert: 'Please add a reason before rejecting.'
        return
      end
      subscription.reject!(current_employee, note: note)
      log_action!('rejected', subscription: subscription, notes: note)
      redirect_to staff_subscription_requests_path, notice: "Rejected #{subscription.user.display_name}."
    end
  end
end
