class Payment < ActiveRecord::Base
  belongs_to :order
  belongs_to :customer, optional: true
  belongs_to :khata_receipt, optional: true

  validates :amount_cents, numericality: { greater_than: 0 }
  before_validation :assign_share_token, on: :create

  def amount
    amount_cents.to_f / 100.0
  end

  def ensure_share_token!
    return share_token if share_token.present?

    assign_share_token
    update_column(:share_token, share_token) if persisted?
    share_token
  end

  private

  def assign_share_token
    return if share_token.present?

    8.times do
      candidate = SecureRandom.hex(16)
      unless self.class.exists?(share_token: candidate)
        self.share_token = candidate
        return
      end
    end
    self.share_token = SecureRandom.hex(24)
  end
end
