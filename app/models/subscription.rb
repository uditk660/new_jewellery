class Subscription < ActiveRecord::Base
  STATUSES = %w[pending active rejected cancelled suspended].freeze
  SOURCES = %w[user_request staff_grant].freeze

  belongs_to :user
  belongs_to :plan
  belongs_to :reviewed_by, class_name: 'Employee', optional: true
  has_many :audit_logs, dependent: :nullify

  enum :status, { pending: 'pending', active: 'active', rejected: 'rejected', cancelled: 'cancelled', suspended: 'suspended' }

  validates :source, inclusion: { in: SOURCES }
  validate :one_pending_per_user, on: :create

  scope :newest, -> { order(created_at: :desc) }

  def live?
    status == 'active' && ends_at.present? && ends_at >= Time.current
  end

  def expired?
    status == 'active' && ends_at.present? && ends_at < Time.current
  end

  def effective_status
    expired? ? 'expired' : status
  end

  def approve!(employee, note: nil)
    now = Time.current
    update!(
      status: 'active',
      starts_at: now,
      ends_at: now + 1.year,
      reviewed_at: now,
      reviewed_by: employee,
      decision_note: note
    )
  end

  def reject!(employee, note:)
    update!(
      status: 'rejected',
      reviewed_at: Time.current,
      reviewed_by: employee,
      decision_note: note
    )
  end

  def cancel!(employee, note: nil)
    update!(
      status: 'cancelled',
      reviewed_at: Time.current,
      reviewed_by: employee,
      decision_note: note
    )
  end

  def suspend!(employee, note: nil)
    update!(
      status: 'suspended',
      reviewed_at: Time.current,
      reviewed_by: employee,
      decision_note: note
    )
  end

  def reactivate!(employee, note: nil)
    now = Time.current
    new_end = ends_at.present? && ends_at > now ? ends_at : now + 1.year
    update!(
      status: 'active',
      starts_at: starts_at.presence || now,
      ends_at: new_end,
      reviewed_at: now,
      reviewed_by: employee,
      decision_note: note
    )
  end

  def grant!(employee, note: nil)
    now = Time.current
    update!(
      status: 'active',
      source: 'staff_grant',
      starts_at: now,
      ends_at: now + 1.year,
      requested_at: now,
      reviewed_at: now,
      reviewed_by: employee,
      decision_note: note
    )
  end

  private

  def one_pending_per_user
    return unless status == 'pending' && user_id.present?
    if Subscription.where(user_id: user_id, status: 'pending').where.not(id: id).exists?
      errors.add(:base, 'You already have a subscription waiting for approval.')
    end
  end
end
