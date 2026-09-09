class Customer < ActiveRecord::Base
  has_many :orders
  has_many :payments

  validates :phone, presence: true, uniqueness: true
  validates :first_name, presence: true
  validates :email, uniqueness: true, allow_blank: true

  before_validation :normalize

  def self.find_by_phone_loose(phone)
    raw = phone.to_s.strip
    digits = raw.gsub(/\D/, '')
    return nil if raw.blank? && digits.blank?

    where(phone: [raw, digits].reject(&:blank?).uniq).first
  end

  def bill_payload
    {
      id: id,
      name: full_name,
      phone: phone.to_s,
      email: email.to_s,
      gst: gst_number.to_s,
      outstanding: outstanding.to_f,
      initials: initials
    }
  end

  # Return a display-friendly full name for the customer
  def full_name
    [first_name, last_name].compact.join(' ').strip
  end

  def initials
    first = first_name.to_s.strip
    last = last_name.to_s.strip
    letters = "#{first[0]}#{last[0]}".presence || first[0, 2]
    letters.to_s.upcase
  end

  def outstanding
    return 0.0 unless self.class.column_names.include?('balance_cents')
    balance_cents.to_i / 100.0
  end

  # Recompute and persist customer's outstanding balance (sum of remaining across unpaid orders)
  def recompute_balance!
    total_outstanding = orders.where.not(status: 'paid').to_a.sum do |o|
      o.remaining_cents
    end
    update_column(:balance_cents, total_outstanding.to_i)
  end

  private

  def normalize
    self.first_name = first_name.to_s.strip
    self.last_name = last_name.to_s.strip.presence
    self.phone = phone.to_s.gsub(/\s+/, ' ').strip
    self.email = email.to_s.strip.downcase.presence
    self.aadhaar_or_pan = aadhaar_or_pan.to_s.strip.presence
    self.gst_number = gst_number.to_s.strip.upcase.presence
    self.address = address.to_s.strip.presence
  end
end
