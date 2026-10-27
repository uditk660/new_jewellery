class JewelryItem < ActiveRecord::Base
  validates :name, presence: true
  validates :metal_id, presence: true
  validates :purity_id, presence: true
  validates :jewellery_category_id, presence: true
  validates :price_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :sku, presence: true, uniqueness: true
  validates :quantity, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :weight_grams, presence: true, numericality: { greater_than: 0 }

  belongs_to :metal, optional: true
  belongs_to :purity, optional: true
  belongs_to :jewellery_category, optional: true
  has_one :inventory_item

  before_validation :normalize_weight
  before_validation :set_sku, on: :create
  before_validation :sync_metal_from_purity
  before_validation :apply_calculated_price
  validate :purity_belongs_to_metal
  validate :category_belongs_to_metal
  validate :purity_has_sufficient_weight
  around_save :apply_purity_stock_change
  around_destroy :restore_purity_stock_on_destroy

  scope :kept, -> { column_names.include?('archived') ? where(archived: false) : all }
  scope :archived_only, -> { column_names.include?('archived') ? where(archived: true) : none }
  scope :on_tray, -> { kept.where('quantity > 0') }
  scope :stock_out, -> { kept.where('COALESCE(quantity, 0) <= 0') }
  scope :available_for_sale, -> {
    rel = on_tray
    rel = rel.joins(:metal).where(metals: { active: true }) if Metal.column_names.include?('active')
    rel = rel.joins(:purity).where(purities: { active: true }) if Purity.column_names.include?('active')
    rel
  }
  scope :with_inactive_master, -> {
    rel = left_joins(:metal, :purity)
    parts = []
    parts << 'metals.active = 0' if Metal.column_names.include?('active')
    parts << 'purities.active = 0' if Purity.column_names.include?('active')
    parts.any? ? rel.where(parts.join(' OR ')) : none
  }

  def sale_locked?
    metal&.rate_board_locked? || purity&.rate_board_locked?
  end

  def archived?
    has_attribute?(:archived) && self[:archived]
  end

  def amendable?
    return false if archived?
    return false if sale_locked?
    true
  end

  def sellable?
    return false if quantity.to_i <= 0
    return false if archived?
    return false if sale_locked?
    true
  end

  def sync_metal_from_purity
    self.metal_id = purity.metal_id if purity
  end

  def normalize_weight
    self.weight_grams = nil if weight_grams.blank?
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

  def price=(rupees)
    self.price_cents = Paise.from_rupees(rupees)
  end

  def purity_price_per_gram
    return nil unless purity && purity.updated_price.present?
    value = purity.updated_price.to_f
    value.positive? ? value : nil
  end

  def valuation_quantity
    qty = quantity.to_i
    qty < 1 ? 1 : qty
  end

  # Per piece: purity rate × weight (g)
  def unit_amount
    rate = effective_price_per_gram
    return 0.0 if rate.nil?
    Paise.rupees(unit_cents)
  end

  def unit_cents
    rate = effective_price_per_gram
    return 0 if rate.nil?
    Paise.from_rupees(Paise.dec!(rate) * Paise.dec!(weight_grams))
  end

  # Catalogue price: purity rate × weight (g) × quantity (pcs)
  def catalogue_amount
    Paise.rupees(unit_cents * valuation_quantity)
  end

  # Tray value at the current board: rate × weight (g) × pieces on tray.
  def stock_amount
    qty = quantity.to_i
    return 0.0 if qty <= 0

    Paise.rupees(unit_cents * qty)
  end

  def computed_price
    unit_amount.positive? ? unit_amount : price.to_f
  end

  def effective_price_per_gram
    return purity_price_per_gram if purity_price_per_gram.present?
    return nil unless metal
    ms = metal.respond_to?(:metal_stocks) ? metal.metal_stocks.order(created_at: :desc).first : nil
    if ms && ms.price_cents_per_gram.to_i > 0
      ms.price_cents_per_gram.to_f / 100.0
    else
      nil
    end
  end

  def apply_calculated_price
    self.price_cents = unit_cents * valuation_quantity
  end

  def invoice_hsn
    jewellery_category&.try(:hsn_code).presence || metal&.try(:hsn_code).presence.to_s
  end

  def default_making_percent
    cat = jewellery_category&.try(:default_making_charge_percent)
    pur = purity&.try(:making_charge_percent)
    (cat.presence || pur.presence || 0).to_f
  end

  def bill_payload
    {
      id: id,
      name: name,
      sku: sku.to_s,
      hsn: invoice_hsn.to_s,
      quantity: quantity.to_i,
      weight_grams: weight_grams.to_f,
      price_per_gram: effective_price_per_gram.to_f,
      making_percent: default_making_percent,
      metal: metal&.name.to_s,
      metal_id: metal_id,
      colour: metal&.try(:chip_colour).presence || '#c9a227',
      purity: purity&.name.to_s,
      purity_label: purity&.try(:hallmark_label).to_s,
      category: jewellery_category&.try(:display_name).to_s
    }
  end

  def consumed_grams
    (weight_grams.to_d.round(2) * [quantity.to_i, 0].max).round(2)
  end

  # Put a sold piece back on the tray. This is the inverse of a sale, not a new
  # catalogue registration — hallmark bulk weight must not be consumed again.
  def restore_to_tray!(qty)
    add = qty.to_i
    return quantity.to_i if add <= 0

    self.class.where(id: id).update_all(['quantity = COALESCE(quantity, 0) + ?', add])
    reload
    quantity.to_i
  end

  private

  def previous_consumed_grams
    return 0.to_d unless persisted?

    (weight_grams_in_database.to_d.round(2) * quantity_in_database.to_i).round(2)
  end

  def purity_has_sufficient_weight
    return if purity.blank? || !purity.class.column_names.include?('available_grams')

    needed = consumed_grams
    return unless needed.positive?

    remaining = purity.available_grams.to_d
    remaining += previous_consumed_grams if persisted? && purity_id.to_s == purity_id_in_database.to_s
    return if remaining >= needed

    metal_name = purity.metal&.name || 'this metal'
    errors.add(
      :weight_grams,
      "exceeds remaining #{purity.name} weight (#{format('%.2f', remaining)} g) for #{metal_name}."
    )
  end

  def apply_purity_stock_change
    unless self.class.connection.column_exists?(:purities, :available_grams)
      yield
      return
    end

    previous_purity_id = persisted? ? purity_id_in_database : nil
    previous_grams = previous_consumed_grams
    next_purity_id = purity_id
    next_grams = consumed_grams

    if previous_purity_id == next_purity_id && previous_grams == next_grams
      yield
      return
    end

    yielded = false
    self.class.transaction do
      if next_purity_id.present? && next_grams.positive?
        remaining = Purity.lock.where(id: next_purity_id).pick(:available_grams).to_d
        remaining += previous_grams if previous_purity_id == next_purity_id
        if remaining < next_grams
          target = Purity.includes(:metal).find(next_purity_id)
          metal_name = target.metal&.name || 'this metal'
          errors.add(
            :weight_grams,
            "exceeds remaining #{target.name} weight (#{format('%.2f', remaining)} g) for #{metal_name}."
          )
          raise ActiveRecord::Rollback
        end
      end

      if previous_purity_id.present? && previous_grams.positive?
        old_purity = Purity.lock.find(previous_purity_id)
        old_purity.update!(available_grams: old_purity.available_grams.to_d + previous_grams)
      end

      if next_purity_id.present? && next_grams.positive?
        target = Purity.lock.find(next_purity_id)
        target.update!(available_grams: target.available_grams.to_d - next_grams)
      end

      yielded = true
      yield
    end
    throw :abort unless yielded
  end

  def restore_purity_stock_on_destroy
    unless self.class.connection.column_exists?(:purities, :available_grams)
      yield
      return
    end

    pid = purity_id
    grams = consumed_grams
    self.class.transaction do
      if pid.present? && grams.positive?
        purity_row = Purity.lock.find_by(id: pid)
        purity_row.update!(available_grams: purity_row.available_grams.to_d + grams) if purity_row
      end
      yield
    end
  end
end
