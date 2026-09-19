class LedgerEntry < ActiveRecord::Base
  KINDS = %w[opening debit credit].freeze

  belongs_to :customer

  validates :kind, inclusion: { in: KINDS }
  validates :entry_date, presence: true
  validates :amount_cents, numericality: { only_integer: true, greater_than: 0 }
  validates :note, length: { maximum: 160 }, allow_blank: true

  before_validation :normalize

  def amount
    amount_cents.to_f / 100.0
  end

  def amount=(rupees)
    self.amount_cents = (rupees.to_s.gsub(',', '').to_f * 100).round
  end

  def credit?
    kind.to_s == 'credit'
  end

  def signed_cents
    credit? ? -amount_cents.to_i : amount_cents.to_i
  end

  def debit_amount
    credit? ? 0.0 : amount
  end

  def credit_amount
    credit? ? amount : 0.0
  end

  def kind_label
    case kind.to_s
    when 'opening' then 'Opening'
    when 'debit' then 'Charge'
    when 'credit' then 'Receipt'
    else kind.to_s.titleize
    end
  end

  private

  def normalize
    self.kind = kind.to_s.strip.downcase.presence
    self.note = note.to_s.strip.presence
    self.entry_date ||= Time.zone.today
  end
end
