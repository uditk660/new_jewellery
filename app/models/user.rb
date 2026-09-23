class User < ActiveRecord::Base
  if defined?(Devise)
    devise :database_authenticatable, :registerable,
           :recoverable, :rememberable, :validatable
  end

  has_many :subscriptions, dependent: :destroy
  has_one :shop_profile, dependent: :destroy

  before_validation :normalize_mobile_number

  validates :shop_name, :full_name, :phone, presence: true, on: :create
  validates :password_confirmation, presence: true, on: :create
  validates :phone, format: {
    with: /\A\+91\d{10}\z/,
    message: 'must be +91 and exactly 10 digits'
  }, allow_blank: true

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

  def mobile_digits
    digits = phone.to_s.gsub(/\D/, '')
    digits = digits.sub(/\A91/, '') if digits.length > 10 && digits.start_with?('91')
    digits.last(10)
  end

  private

  def normalize_mobile_number
    return if phone.blank?

    digits = phone.to_s.gsub(/\D/, '')
    digits = digits.sub(/\A91/, '') if digits.length > 10 && digits.start_with?('91')
    self.phone = "+91#{digits}" if digits.length == 10
  end
end
