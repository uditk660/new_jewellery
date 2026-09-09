class Order < ActiveRecord::Base
  has_many :line_items, dependent: :destroy
  has_many :payments, dependent: :destroy
  belongs_to :customer, optional: true
  validates :status, presence: true

  before_validation :assign_share_token, on: :create
  before_create :set_invoice_and_date

  after_update :decrement_inventory_on_payment

  STATUSES = %w[pending paid failed cancelled]

  # Default tax rates (percent)
  DEFAULT_CGST_RATE = 1.5
  DEFAULT_IGST_RATE = 1.5

  def total_cents
    line_items.sum('price_cents * quantity')
  end

  # Return the CGST rate for this order, falling back to the default if not set
  def cgst_rate_or_default
    cgst_rate.nil? ? DEFAULT_CGST_RATE : cgst_rate.to_f
  end

  # Return the second CGST rate for this order, falling back to the default if not set
  def igst_rate_or_default
    igst_rate.nil? ? DEFAULT_IGST_RATE : igst_rate.to_f
  end

  def total
    total_cents.to_f / 100.0
  end

  def total_cents_with_taxes_cached
    # prefer stored tax cents if present, else compute using rates
    if (self.cgst_cents && self.cgst_cents.to_i > 0) || (self.igst_cents && self.igst_cents.to_i > 0)
      taxable = taxable_amount_cents
      taxable + (cgst_cents.to_i) + (igst_cents.to_i)
    else
      total_cents_with_taxes(cgst_rate: cgst_rate_or_default, igst_rate: igst_rate_or_default)
    end
  end

  def paid_cents
    payments.sum(:amount_cents).to_i
  end

  def remaining_cents
    [(bill_breakdown[:total] * 100).round - paid_cents, 0].max
  end

  def paid_amount
    paid_cents / 100.0
  end

  def remaining_amount
    remaining_cents / 100.0
  end

  # Float totals used on the bill card and payment desk.
  # Metal comes from each line's stored rate (the board at raise), not today's rates.
  def bill_breakdown
    sub = line_items.to_a.sum { |li| li.line_amount }
    disc = discount.to_f
    chg = charges.to_f
    taxable = sub - disc + chg
    cgst_r = cgst_rate_or_default
    igst_r = igst_rate_or_default
    cgst = taxable * cgst_r / 100.0
    igst = taxable * igst_r / 100.0
    tot = taxable + cgst + igst
    paid = paid_amount
    {
      subtotal: sub,
      discount: disc,
      charges: chg,
      taxable: taxable,
      cgst_rate: cgst_r,
      igst_rate: igst_r,
      cgst: cgst,
      igst: igst,
      total: tot,
      paid: paid,
      remaining: [tot - paid, 0].max
    }
  end

  def displayed_cgst
    stored_tax? ? (cgst_cents.to_i / 100.0) : (cgst_amount_cents(cgst_rate_or_default) / 100.0)
  end

  def displayed_igst
    stored_tax? ? (igst_cents.to_i / 100.0) : (igst_amount_cents(igst_rate_or_default) / 100.0)
  end

  def stored_tax?
    cgst_cents.to_i.positive? || igst_cents.to_i.positive?
  end

  def add_item(jewelry_item, quantity = 1)
    li = line_items.find_by(jewelry_item_id: jewelry_item.id)
    if li
      li.quantity += quantity
      li.price_cents = jewelry_item.price_cents
      li.save
    else
      # weight will be set by caller if provided in attributes
      line_items.create!(jewelry_item_id: jewelry_item.id, price_cents: jewelry_item.price_cents, quantity: quantity)
    end
  end

  # billing helpers
  def subtotal_cents
    # include per-line amounts (price * qty + making + additional per-item)
    computed_total_cents
  end

  def subtotal
    subtotal_cents.to_f / 100.0
  end

  def discount_cents
    (discount.to_f * 100).to_i
  end

  def charges_cents
    (charges.to_f * 100).to_i
  end

  def taxable_amount_cents
    subtotal_cents - discount_cents + charges_cents
  end

  # compute tax amounts (in cents) given a rate percent
  def cgst_amount_cents(rate_percent)
    (taxable_amount_cents * rate_percent / 100.0).to_i
  end

  def igst_amount_cents(rate_percent)
    (taxable_amount_cents * rate_percent / 100.0).to_i
  end

  def total_cents_with_taxes(cgst_rate: 0, igst_rate: 0)
    taxable = taxable_amount_cents
    taxable + cgst_amount_cents(cgst_rate) + igst_amount_cents(igst_rate)
  end

  def total_with_taxes(cgst_rate: 0, igst_rate: 0)
    total_cents_with_taxes(cgst_rate: cgst_rate, igst_rate: igst_rate).to_f / 100.0
  end

  # Computed totals derived from LineItem#line_amount (per-gram * net_weight * qty + making)
  def computed_total_cents
    line_items.sum { |li| li.line_amount_cents }
  end

  def computed_total
    computed_total_cents.to_f / 100.0
  end

  def ensure_share_token!
    return share_token if share_token.present?

    assign_share_token
    update_column(:share_token, share_token) if persisted?
    share_token
  end

  private

  def assign_share_token
    return if share_token.present?

    8.times do
      candidate = SecureRandom.hex(16)
      unless self.class.exists?(share_token: candidate)
        self.share_token = candidate
        return
      end
    end
    self.share_token = SecureRandom.hex(24)
  end

  def set_invoice_and_date
  self.sale_date ||= Time.zone.today
    today_invoices_count = Order.where(sale_date: self.sale_date).count + 1
    self.invoice_number ||= "INV-#{self.sale_date.strftime('%Y%m%d')}-#{today_invoices_count.to_s.rjust(3, '0')}"
  end

  def decrement_inventory_on_payment
  Rails.logger.warn "Order##{id} after_update fired (status=#{status.inspect}) previous_changes=#{previous_changes.inspect}"
  # if the order is in paid state and we haven't decremented stock for it yet, proceed
  return unless status == 'paid'
  return if self.respond_to?(:stock_decremented_at) && self.stock_decremented_at.present?

  Rails.logger.warn "Order##{id} status is paid and stock not yet decremented - processing #{line_items.count} line_items"

    Order.transaction do
      line_items.each do |li|
        ji = li.jewelry_item
        unless ji
          Rails.logger.warn "Order##{id} line_item #{li.id} has no associated jewelry_item"
          next
        end

        qty_to_subtract = li.quantity.to_i
        # log current quantity
  Rails.logger.warn "JewelryItem##{ji.id} current quantity=#{ji.quantity.inspect}, subtract=#{qty_to_subtract}"

        # Use an atomic SQL update to avoid race conditions and prevent negative quantities.
        # SQLite does not have GREATEST(), so use a CASE expression which works across adapters.
        JewelryItem.where(id: ji.id).update_all(["quantity = CASE WHEN quantity - ? < 0 THEN 0 ELSE quantity - ? END", qty_to_subtract, qty_to_subtract])

        # reload and log the new quantity for visibility
        ji.reload
        Rails.logger.warn "JewelryItem##{ji.id} new quantity=#{ji.quantity.inspect}"
      end

      # mark that we've decremented stock to make operation idempotent
        if self.respond_to?(:stock_decremented_at)
        update_column(:stock_decremented_at, Time.zone.now)
      end
    end
  end
end
