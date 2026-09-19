class Store < ActiveRecord::Base
  has_many :metal_stocks, dependent: :destroy

  validates :name, presence: true, uniqueness: { case_sensitive: false }, length: { maximum: 80 }
  validates :location, length: { maximum: 120 }, allow_blank: true

  before_validation :normalize

  scope :ordered, -> { order(:name) }

  def location_label
    location.presence || 'House store'
  end

  def vault_grams
    metal_stocks.sum { |ms| ms.available_grams.to_i }
  end

  def vault_value
    metal_stocks.sum(&:stock_value)
  end

  def vault_metal_count
    metal_stocks.size
  end

  def bare?
    metal_stocks.empty?
  end

  def empty_vault?
    metal_stocks.any? && metal_stocks.all?(&:empty?)
  end

  def light_vault?
    metal_stocks.any?(&:light?)
  end

  def missing_metals
    tracked = metal_stocks.map(&:metal_id)
    scope = Metal.ordered
    tracked.any? ? scope.where.not(id: tracked) : scope
  end

  private

  def normalize
    self.name = name.to_s.gsub(/\s+/, ' ').strip.presence
    self.location = location.to_s.gsub(/\s+/, ' ').strip.presence
  end
end
