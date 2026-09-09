module Staff
  class SubscriptionsController < BaseController
    def index
      @subscriptions = Subscription.includes(:user, :plan, :reviewed_by).newest
      @subscriptions = @subscriptions.where(status: params[:status]) if params[:status].present?
    end

    def show
      @subscription = Subscription.includes(:user, :plan, :reviewed_by, :audit_logs).find(params[:id])
      @logs = @subscription.audit_logs.newest.includes(:employee)
    end

    def new
      @subscription = Subscription.new
      @users = User.order(:email)
      @plans = Plan.active
    end

    def create
      @users = User.order(:email)
      @plans = Plan.active
      user = User.find_by(id: params.dig(:subscription, :user_id))
      plan = Plan.find_by(id: params.dig(:subscription, :plan_id))
      unless user && plan
        @subscription = Subscription.new
        flash.now[:alert] = 'Choose both a store account and a plan.'
        render :new and return
      end

      subscription = user.subscriptions.build(plan: plan, source: 'staff_grant')
      subscription.grant!(current_employee, note: params.dig(:subscription, :decision_note))
      log_action!('granted', subscription: subscription, notes: params.dig(:subscription, :decision_note))
      redirect_to staff_subscription_path(subscription), notice: "Activated 1-year #{plan.name} for #{user.display_name}."
    rescue ActiveRecord::RecordInvalid => e
      @subscription = e.record
      flash.now[:alert] = e.record.errors.full_messages.to_sentence
      render :new
    end

    def cancel
      subscription = Subscription.find(params[:id])
      subscription.cancel!(current_employee, note: params[:decision_note])
      log_action!('cancelled', subscription: subscription, notes: params[:decision_note])
      redirect_to staff_subscription_path(subscription), notice: 'Subscription cancelled.'
    end

    def suspend
      subscription = Subscription.find(params[:id])
      subscription.suspend!(current_employee, note: params[:decision_note])
      log_action!('suspended', subscription: subscription, notes: params[:decision_note])
      redirect_to staff_subscription_path(subscription), notice: 'Subscription suspended. The store cannot use the dashboard.'
    end

    def reactivate
      subscription = Subscription.find(params[:id])
      subscription.reactivate!(current_employee, note: params[:decision_note])
      log_action!('reactivated', subscription: subscription, notes: params[:decision_note])
      redirect_to staff_subscription_path(subscription), notice: 'Subscription reactivated.'
    end
  end
end
