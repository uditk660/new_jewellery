class ContactInquiry < ActiveRecord::Base
  STATUSES = %w[new read closed].freeze

  validates :name, presence: true, length: { maximum: 120 }
  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :message, presence: true, length: { minimum: 10, maximum: 4000 }
  validates :subject, length: { maximum: 160 }, allow_blank: true
  validates :phone, length: { is: 10 }, allow_blank: true
  validates :status, inclusion: { in: STATUSES }

  before_validation :normalize

  private

  def normalize
    self.name = name.to_s.strip
    self.email = email.to_s.strip.downcase
    self.phone = phone.to_s.gsub(/\D/, '')
    self.phone = nil if phone.blank?
    self.subject = subject.to_s.strip.presence
    self.message = message.to_s.strip
    self.status = 'new' if status.blank?
  end
end
