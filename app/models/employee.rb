class Employee < ActiveRecord::Base
  devise :database_authenticatable, :rememberable, :validatable

  has_many :reviewed_subscriptions, class_name: 'Subscription', foreign_key: :reviewed_by_id, dependent: :nullify
  has_many :audit_logs, dependent: :nullify

  validates :name, presence: true
end
