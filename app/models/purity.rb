class Purity < ActiveRecord::Base
  HALLMARK_STANDARDS = ['BIS', 'None', 'Other'].freeze

  belongs_to :metal, inverse_of: :purities
  has_many :jewelry_items, dependent: :nullify

  validates :name, presence: true, uniqueness: { scope: :metal_id, case_sensitive: false }
  validates :purity_percent, numericality: { greater_than: 0, less_than_or_equal_to: 100 }, allow_nil: true
  validates :updated_price, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :wastage_percent, :making_charge_percent, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :available_grams, numericality: { greater_than_or_equal_to: 0 }, if: -> { self.class.column_names.include?('available_grams') }
  validates :hallmark_standard, inclusion: { in: HALLMARK_STANDARDS }, allow_blank: true

  before_destroy :ensure_unused
  before_validation :normalize

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(Arel.sql('COALESCE(position, 0)'), :name) }

  def hallmark_label
    bits = [name]
    bits << "#{trimmed_percent}%" if purity_percent.present?
    bits << fineness if fineness.present?
    bits.join(' · ')
  end

  def available_weight_label
    "#{format('%.2f', available_grams.to_f)} g"
  end

  def catalogue_option_label
    "#{hallmark_label} · #{available_weight_label}"
  end

  def trimmed_percent
    return nil if purity_percent.blank?
    v = purity_percent.to_f
    (v == v.to_i) ? v.to_i.to_s : ('%g' % v)
  end

  private

  def normalize
    self.name = name.to_s.strip
    self.fineness = fineness.to_s.gsub(/\s/, '').presence
    self.hallmark_standard = hallmark_standard.to_s.strip.presence
    self.active = true if active.nil?
    self.available_grams = 0 if self.class.column_names.include?('available_grams') && available_grams.nil?
  end

  def ensure_unused
    return unless jewelry_items.exists?

    errors.add(:base, 'This hallmark is used on catalogue pieces and cannot be removed.')
    throw :abort
  end
end
