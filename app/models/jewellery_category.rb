class JewelleryCategory < ActiveRecord::Base
  GENDERS = ['Women', 'Men', 'Unisex', 'Kids'].freeze

  belongs_to :metal, inverse_of: :jewellery_categories
  has_many :jewelry_items, dependent: :nullify

  validates :name, presence: true, uniqueness: { scope: :metal_id, case_sensitive: false }
  validates :gender, inclusion: { in: GENDERS }, allow_blank: true
  validates :default_making_charge_percent, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  before_destroy :ensure_unused
  before_validation :normalize

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(Arel.sql('COALESCE(position, 0)'), :name) }

  def display_name
    gender.present? ? "#{name} (#{gender})" : name
  end

  private

  def normalize
    self.name = name.to_s.strip
    self.gender = gender.to_s.strip.presence
    self.active = true if active.nil?
  end

  def ensure_unused
    return unless jewelry_items.exists?

    errors.add(:base, 'This category is used on catalogue pieces and cannot be removed.')
    throw :abort
  end
end
