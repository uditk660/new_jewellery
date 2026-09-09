class User < ActiveRecord::Base
  if defined?(Devise)
    devise :database_authenticatable, :registerable,
           :recoverable, :rememberable, :validatable
  end

  has_many :subscriptions, dependent: :destroy
  has_one :shop_profile, dependent: :destroy

  def current_subscription
    subscriptions.newest.first
  end

  def active_subscription
    subscriptions.where(status: 'active').where('ends_at >= ?', Time.current).order(ends_at: :desc).first
  end

  def subscription_live?
    active_subscription.present?
  end

  def display_name
    shop_profile&.shop_name.presence || shop_name.presence || full_name.presence || email.to_s.split('@').first
  end

  def shop_setup_complete?
    shop_profile&.completed?
  end
end
