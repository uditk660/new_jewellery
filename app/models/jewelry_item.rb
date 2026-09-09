class JewelryItem < ActiveRecord::Base
  validates :name, presence: true
  validates :metal_id, presence: true
  validates :purity_id, presence: true
  validates :price_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :sku, presence: true, uniqueness: true
  validates :quantity, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :weight_grams, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  belongs_to :metal, optional: true
  belongs_to :purity, optional: true
  belongs_to :jewellery_category, optional: true

  before_validation :set_sku, on: :create
  before_validation :sync_metal_from_purity
  validate :purity_belongs_to_metal
  validate :category_belongs_to_metal

  scope :available_for_sale, -> { where('quantity > 0') }

  def sync_metal_from_purity
    self.metal_id = purity.metal_id if purity
  end

  def purity_belongs_to_metal
    return if purity.blank? || metal_id.blank?
    return if purity.metal_id == metal_id

    errors.add(:purity_id, 'must belong to the selected metal')
  end

  def category_belongs_to_metal
    return if jewellery_category.blank? || metal_id.blank?
    return if jewellery_category.metal_id == metal_id

    errors.add(:jewellery_category_id, 'must belong to the selected metal')
  end

  def set_sku
    return if sku.present?
    # generate an 11-character SKU: 'J' + 10 alphanumeric chars
    10.times do
      candidate = "J#{SecureRandom.alphanumeric(10).upcase}"
      unless self.class.exists?(sku: candidate)
        self.sku = candidate
        break
      end
    end
    # fallback deterministic-ish SKU (should be rare)
    self.sku ||= "J#{SecureRandom.alphanumeric(10).upcase}"
  end

  def price
    price_cents.to_f / 100.0
  end

  def price=(dollars)
    self.price_cents = (dollars.to_f * 100).round
  end

  # Returns purity price per gram (decimal) if a purity with updated_price exists
  def purity_price_per_gram
    return nil unless purity && purity.updated_price.present?
    purity.updated_price.to_f
  end

  # Compute item price from purity price per gram * weight_grams where available,
  # otherwise fall back to stored item price
  def computed_price
    if effective_price_per_gram && weight_grams.present?
      (effective_price_per_gram * weight_grams.to_f).round(2)
    else
      price.to_f
    end
  end

  # Returns the effective per-gram price to use for computing item price.
  # Preference order: purity.updated_price -> latest metal_stock.price_cents_per_gram -> nil
  def effective_price_per_gram
    return purity_price_per_gram if purity_price_per_gram.present?
    return nil unless metal
    # pick latest metal_stock record for this metal if present
    ms = metal.respond_to?(:metal_stocks) ? metal.metal_stocks.order(created_at: :desc).first : nil
    if ms && ms.price_cents_per_gram.to_i > 0
      ms.price_cents_per_gram.to_f / 100.0
    else
      nil
    end
  end
end
