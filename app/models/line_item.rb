class LineItem < ActiveRecord::Base
  belongs_to :order
  belongs_to :jewelry_item

  validates :quantity, numericality: { only_integer: true, greater_than: 0 }
  validates :price_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :weight, numericality: { greater_than: 0 }
  validates :gross_weight, numericality: { greater_than_or_equal_to: 0 }
  validates :net_weight, numericality: { greater_than_or_equal_to: 0 }
  validates :making_charge, numericality: { greater_than_or_equal_to: 0 }
  validates :additional_charge, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validate :quantity_within_catalogue_stock

  def quantity_within_catalogue_stock
    return if jewelry_item.blank? || quantity.blank?

    available = jewelry_item.quantity.to_i
    return unless quantity.to_i > available

    errors.add(:quantity, "cannot exceed remaining stock (#{available} pcs)")
  end

  def total_cents
    # include making charge per-line (converted to cents) and additional charge per-item
    base = (price_cents * quantity)
    making_c = (making_charge.to_f * 100).to_i
    additional_c = ((additional_charge.to_f * 100).to_i * quantity)
    base + making_c + additional_c
  end

  def total
    total_cents.to_f / 100.0
  end

  # Metal value stored on the bill (₹/g × net g × qty at the time it was raised).
  def metal_amount
    return rate.to_f if rate.to_f.positive?

    (per_gram_price.to_f * net_weight.to_f * quantity.to_i)
  end

  def rate_per_gram_used
    den = net_weight.to_f * quantity.to_i
    den.positive? ? (metal_amount / den) : per_gram_price.to_f
  end

  # Price per gram to be used for calculations. Prefer jewelry_item.effective_price_per_gram
  # (set by JewelryItem model) and fall back to stored price_cents.
  def per_gram_price
    if jewelry_item && jewelry_item.respond_to?(:effective_price_per_gram) && jewelry_item.effective_price_per_gram.present?
      jewelry_item.effective_price_per_gram.to_f
    else
      (price_cents || 0).to_f / 100.0
    end
  end

  def making_percent
    metal = metal_amount
    metal.positive? ? (making_charge.to_f / metal * 100.0) : 0.0
  end

  # Compute the line amount as: metal + making + additional per piece × qty
  def line_amount
    metal_amount + making_charge.to_f + additional_charge.to_f * quantity.to_i
  end

  def line_amount_cents
    (line_amount * 100).to_i
  end
end
