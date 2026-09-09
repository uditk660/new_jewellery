class ShopProfile < ActiveRecord::Base
  belongs_to :user

  INDIAN_STATES = [
    'Andhra Pradesh', 'Arunachal Pradesh', 'Assam', 'Bihar', 'Chhattisgarh', 'Goa', 'Gujarat',
    'Haryana', 'Himachal Pradesh', 'Jharkhand', 'Karnataka', 'Kerala', 'Madhya Pradesh',
    'Maharashtra', 'Manipur', 'Meghalaya', 'Mizoram', 'Nagaland', 'Odisha', 'Punjab',
    'Rajasthan', 'Sikkim', 'Tamil Nadu', 'Telangana', 'Tripura', 'Uttar Pradesh', 'Uttarakhand',
    'West Bengal', 'Andaman and Nicobar Islands', 'Chandigarh', 'Dadra and Nagar Haveli and Daman and Diu',
    'Delhi', 'Jammu and Kashmir', 'Ladakh', 'Lakshadweep', 'Puducherry'
  ].freeze

  JEWELLER_TYPES = ['Retailer', 'Wholesaler', 'Manufacturer', 'Retailer & Manufacturer'].freeze

  validates :shop_name, :owner_name, :phone, :email, presence: true
  validates :address_line1, :city, :state, :pincode, presence: true
  validates :gstin, :registration_number, :bis_hallmark_licence, presence: true
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :pincode, format: { with: /\A\d{6}\z/, message: 'must be a 6-digit PIN code' }
  validates :gstin, format: { with: /\A[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]\z/i, message: 'must be a valid 15-character GSTIN' }
  validates :pan, format: { with: /\A[A-Z]{5}[0-9]{4}[A-Z]\z/i, allow_blank: true, message: 'must be a valid PAN' }
  validates :state, inclusion: { in: INDIAN_STATES }
  validates :jeweller_type, inclusion: { in: JEWELLER_TYPES }, allow_blank: true

  before_validation :normalize_codes

  def completed?
    completed_at.present?
  end

  def formatted_address
    [address_line1, address_line2, [city, state, pincode].reject(&:blank?).join(', '), country].reject(&:blank?).join("\n")
  end

  private

  def normalize_codes
    self.gstin = gstin.to_s.gsub(/\s/, '').upcase.presence
    self.pan = pan.to_s.gsub(/\s/, '').upcase.presence
    self.ifsc = ifsc.to_s.gsub(/\s/, '').upcase.presence
    self.pincode = pincode.to_s.gsub(/\s/, '').presence
  end
end
