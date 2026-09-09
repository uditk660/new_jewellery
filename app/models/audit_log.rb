class AuditLog < ActiveRecord::Base
  belongs_to :employee, optional: true
  belongs_to :user, optional: true
  belongs_to :subscription, optional: true
  belongs_to :plan, optional: true

  validates :action, presence: true

  scope :newest, -> { order(created_at: :desc) }

  def self.record!(employee:, action:, user: nil, subscription: nil, plan: nil, notes: nil, ip: nil)
    create!(
      employee: employee,
      user: user,
      subscription: subscription,
      plan: plan || subscription&.plan,
      action: action,
      notes: notes,
      ip_address: ip
    )
  end
end
