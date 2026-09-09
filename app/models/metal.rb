class Metal < ActiveRecord::Base
  BASE_UNITS = ['gram', 'carat'].freeze
  COLOURS = {
    'Gold' => '#c9a227',
    'Silver' => '#c5cdd8',
    'Platinum' => '#9aa3b2',
    'Rose Gold' => '#b76e79'
  }.freeze

  has_many :purities, dependent: :destroy, inverse_of: :metal
  has_many :jewellery_categories, dependent: :destroy, inverse_of: :metal
  has_many :jewelry_items, class_name: 'JewelryItem', foreign_key: 'metal_id', dependent: :nullify
  has_many :metal_stocks, dependent: :destroy

  accepts_nested_attributes_for :purities, allow_destroy: true, reject_if: :blank_nested_name?
  accepts_nested_attributes_for :jewellery_categories, allow_destroy: true, reject_if: :blank_nested_name?

  validates :name, presence: true, uniqueness: { case_sensitive: false }
  validates :code, uniqueness: { case_sensitive: false, allow_blank: true }
  validates :base_unit, inclusion: { in: BASE_UNITS }, allow_blank: true

  before_validation :normalize

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(Arel.sql('COALESCE(display_order, 0)'), :name) }

  def purity_names
    purities.map(&:name).reject(&:blank?)
  end

  def category_names
    jewellery_categories.map(&:name).reject(&:blank?)
  end

  def chip_colour
    colour.presence || COLOURS[name] || '#c9a227'
  end

  private

  def normalize
    self.name = name.to_s.strip
    self.code = code.to_s.strip.upcase.presence
    self.hsn_code = hsn_code.to_s.strip.presence
    self.colour = colour.to_s.strip.presence
    self.base_unit = base_unit.presence || 'gram'
    self.active = true if active.nil?
  end

  def blank_nested_name?(attrs)
    attrs['id'].blank? && attrs['name'].to_s.strip.blank?
  end
end
