class Customer < ActiveRecord::Base
  has_many :orders
  has_many :payments
  has_many :ledger_entries, dependent: :restrict_with_error

  validates :phone, presence: true, uniqueness: true
  validates :first_name, presence: true
  validates :email, uniqueness: true, allow_blank: true

  before_validation :normalize
  before_validation :ensure_client_code

  attr_accessor :house_name_for_code

  validates :client_code, uniqueness: true, allow_blank: true

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

  def card_name
    name = full_name.presence || 'Client'
    short = initials.presence
    short.present? ? "#{name}(#{short})" : name
  end

  def client_ref
    return if client_code.blank?
    client_code.start_with?('#') ? client_code : "##{client_code}"
  end

  def self.house_shop_name
    profile = ShopProfile.order(:id).first if defined?(ShopProfile) && connection.data_source_exists?('shop_profiles')
    return profile.shop_name if profile && profile.shop_name.present?
    user = User.order(:id).first if defined?(User)
    user&.shop_name.presence || user&.try(:display_name) || 'House'
  end

  def self.house_prefix(shop_name = nil)
    name = shop_name.presence || house_shop_name
    words = name.to_s.upcase.scan(/[A-Z0-9]+/).reject { |w| %w[AND THE OF FOR A AN].include?(w) }
    letters = words.map { |w| w[0] }.join
    letters = name.to_s.upcase.gsub(/[^A-Z0-9]/, '') if letters.length < 2
    letters[0, 3].presence || 'HS'
  end

  def self.random_client_token
    alphabet = ('A'..'Z').to_a + ('0'..'9').to_a
    10.times.map { alphabet[SecureRandom.random_number(alphabet.length)] }.join
  end

  def outstanding
    return 0.0 unless self.class.column_names.include?('balance_cents')
    balance_cents.to_i / 100.0
  end

  def journal_cents
    return 0 unless self.class.connection.data_source_exists?('ledger_entries')
    ledger_entries.to_a.sum(&:signed_cents)
  end

  def live_outstanding_cents
    due = orders.reject { |order| order.status.to_s == 'paid' }.sum { |order| order.remaining_cents.to_i }
    due + journal_cents
  end

  def live_outstanding
    live_outstanding_cents / 100.0
  end

  # Bills still due, plus journal opening / charge, less on-account receipts.
  def recompute_balance!
    total_outstanding = orders.where.not(status: 'paid').to_a.sum do |o|
      o.remaining_cents
    end
    total_outstanding += journal_cents
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

  def ensure_client_code
    return unless self.class.column_names.include?('client_code')
    return if client_code.present?
    prefix = self.class.house_prefix(house_name_for_code)
    12.times do
      candidate = "#{prefix}-#{self.class.random_client_token}"
      unless self.class.exists?(client_code: candidate)
        self.client_code = candidate
        return
      end
    end
    self.client_code = "#{prefix}-#{SecureRandom.hex(5).upcase}"
  end
end
