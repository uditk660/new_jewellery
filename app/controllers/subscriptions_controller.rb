class SubscriptionsController < ApplicationController
  skip_before_action :enforce_subscription!
  layout 'onboarding'

  def new
    if current_user.subscription_live?
      redirect_to root_path, notice: 'Your subscription is already active.'
      return
    end

    sub = current_user.current_subscription
    if sub&.pending?
      redirect_to pending_subscription_path
      return
    end
    if sub&.status == 'suspended'
      redirect_to pending_subscription_path
      return
    end

    @plans = Plan.active
  end

  def create
    if current_user.subscription_live? || current_user.subscriptions.pending.exists?
      redirect_to pending_subscription_path
      return
    end

    plan = Plan.active.find(params[:plan_id])
    subscription = current_user.subscriptions.build(
      plan: plan,
      status: 'pending',
      source: 'user_request',
      requested_at: Time.current
    )

    if subscription.save
      redirect_to pending_subscription_path, notice: 'Subscription request submitted. Access opens after staff approval.'
    else
      @plans = Plan.active
      flash.now[:alert] = subscription.errors.full_messages.to_sentence
      render :new
    end
  end

  def pending
    @subscription = current_user.current_subscription
    redirect_to(new_subscription_path) and return if @subscription.nil? && !current_user.subscription_live?
    redirect_to(root_path) and return if current_user.subscription_live?
  end
end
