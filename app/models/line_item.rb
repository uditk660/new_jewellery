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

  # Metal value written on the bill when it was raised (₹/g × net g × qty).
  # A bill never re-reads today's board: `rate` holds the metal total, and
  # `price_cents` holds the per-piece metal value as a fallback for old rows.
  def metal_cents
    stored = Paise.dec!(rate)
    return Paise.from_rupees(stored) if stored.positive?

    price_cents.to_i * quantity.to_i
  end

  def making_cents
    Paise.from_rupees(making_charge)
  end

  def additional_cents
    Paise.from_rupees(additional_charge) * quantity.to_i
  end

  def line_amount_cents
    metal_cents + making_cents + additional_cents
  end

  def total_cents
    line_amount_cents
  end

  def total
    Paise.rupees(total_cents)
  end

  def metal_amount
    Paise.rupees(metal_cents)
  end

  def line_amount
    Paise.rupees(line_amount_cents)
  end

  def net_grams_total
    Paise.dec!(net_weight) * quantity.to_i
  end

  def gross_grams_total
    Paise.dec!(gross_weight) * quantity.to_i
  end

  def rate_per_gram_used
    grams = net_grams_total
    return 0.0 unless grams.positive?

    (BigDecimal(metal_cents) / 100 / grams).round(2, BigDecimal::ROUND_HALF_UP).to_f
  end

  def making_percent
    metal = metal_cents
    metal.positive? ? (making_cents * 100.0 / metal) : 0.0
  end

  # Today's board rate for this piece (used only to prefill new bills).
  def per_gram_price
    if jewelry_item && jewelry_item.respond_to?(:effective_price_per_gram) && jewelry_item.effective_price_per_gram.present?
      jewelry_item.effective_price_per_gram.to_f
    else
      (price_cents || 0).to_f / 100.0
    end
  end
end
