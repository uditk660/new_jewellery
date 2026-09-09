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

  # Price per gram to be used for calculations. Prefer jewelry_item.effective_price_per_gram
  # (set by JewelryItem model) and fall back to stored price_cents.
  def per_gram_price
    if jewelry_item && jewelry_item.respond_to?(:effective_price_per_gram) && jewelry_item.effective_price_per_gram.present?
      jewelry_item.effective_price_per_gram.to_f
    else
      (price_cents || 0).to_f / 100.0
    end
  end

  # Compute the line amount as: per_gram_price * net_weight * quantity + making_charge
  def line_amount
    per_gram = per_gram_price || 0.0
    net = self.net_weight.to_f || 0.0
    qty = self.quantity.to_i || 0
    making = self.making_charge.to_f || 0.0
    additional = (self.additional_charge.to_f || 0.0) * qty
    (per_gram * net * qty) + making + additional
  end

  def line_amount_cents
    (line_amount * 100).to_i
  end
end
