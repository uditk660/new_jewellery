class Order < ActiveRecord::Base
  has_many :line_items, dependent: :destroy
  has_many :payments, dependent: :destroy
  belongs_to :customer, optional: true
  validates :status, presence: true

  before_validation :assign_share_token, on: :create
  before_create :set_invoice_and_date

  after_update :decrement_inventory_on_payment

  STATUSES = %w[pending paid failed cancelled]
  LIVE_STATUSES = %w[pending paid].freeze

  # Intra-state GST on jewellery: CGST + SGST (percent each).
  DEFAULT_CGST_RATE = 1.5
  DEFAULT_SGST_RATE = 1.5

  scope :live, -> { where(status: LIVE_STATUSES) }

  def cgst_rate_or_default
    cgst_rate.nil? ? BigDecimal(DEFAULT_CGST_RATE.to_s) : Paise.dec!(cgst_rate)
  end

  def sgst_rate_or_default
    sgst_rate.nil? ? BigDecimal(DEFAULT_SGST_RATE.to_s) : Paise.dec!(sgst_rate)
  end

  # --- Bill arithmetic, all in whole paise -------------------------------------
  # Metal comes from each line's stored value (the board at raise), never today's board.

  def subtotal_cents
    line_items.to_a.sum(&:line_amount_cents)
  end

  def discount_cents
    Paise.from_rupees(discount)
  end

  def charges_cents
    Paise.from_rupees(charges)
  end

  # New and pending bills take discount and extra charges off the total after
  # CGST + SGST. Bills settled before that rule keep the before-tax figures.
  def discount_after_tax?
    !has_attribute?(:discount_after_tax) || discount_after_tax != false
  end

  def taxable_amount_cents
    discount_after_tax? ? subtotal_cents : subtotal_cents - discount_cents + charges_cents
  end

  def cgst_amount_cents(rate_percent = cgst_rate_or_default)
    Paise.percent_of(taxable_amount_cents, rate_percent)
  end

  def sgst_amount_cents(rate_percent = sgst_rate_or_default)
    Paise.percent_of(taxable_amount_cents, rate_percent)
  end

  # Taxable + CGST + SGST, before any after-tax discount or charges.
  def after_tax_cents
    taxable_amount_cents + cgst_amount_cents + sgst_amount_cents
  end

  def total_cents
    discount_after_tax? ? after_tax_cents - discount_cents + charges_cents : after_tax_cents
  end

  def paid_cents
    if payments.loaded?
      payments.sum { |p| p.amount_cents.to_i }
    else
      payments.sum(:amount_cents).to_i
    end
  end

  # The desk collects whole rupees: the bill is rounded off to the nearest rupee.
  def payable_cents
    Paise.round_rupee(total_cents)
  end

  def round_off_cents
    payable_cents - total_cents
  end

  # Due is always a whole rupee, so ₹3,491.70 owed shows ₹3,492 and a ₹500
  # receipt leaves ₹2,992. A bill with under 50 paise left is settled.
  def remaining_cents
    [Paise.round_rupee(total_cents - paid_cents), 0].max
  end

  def subtotal
    Paise.rupees(subtotal_cents)
  end

  def total
    Paise.rupees(total_cents)
  end

  def paid_amount
    Paise.rupees(paid_cents)
  end

  def remaining_amount
    Paise.rupees(remaining_cents)
  end

  def live?
    LIVE_STATUSES.include?(status.to_s)
  end

  # Figures for the bill card, invoice and payment desk. Rupee values are exact
  # paise / 100, so formatting to two decimals never re-rounds.
  def bill_breakdown
    sub = subtotal_cents
    disc = discount_cents
    chg = charges_cents
    after_rule = discount_after_tax?
    taxable = after_rule ? sub : sub - disc + chg
    cgst_r = cgst_rate_or_default
    sgst_r = sgst_rate_or_default
    cgst = Paise.percent_of(taxable, cgst_r)
    sgst = Paise.percent_of(taxable, sgst_r)
    after_tax = taxable + cgst + sgst
    tot = after_rule ? after_tax - disc + chg : after_tax
    payable = Paise.round_rupee(tot)
    paid = paid_cents
    remaining = [Paise.round_rupee(tot - paid), 0].max
    {
      discount_after_tax: after_rule,
      after_tax: Paise.rupees(after_tax),
      after_tax_cents: after_tax,
      subtotal: Paise.rupees(sub),
      discount: Paise.rupees(disc),
      charges: Paise.rupees(chg),
      taxable: Paise.rupees(taxable),
      cgst_rate: cgst_r.to_f,
      sgst_rate: sgst_r.to_f,
      cgst: Paise.rupees(cgst),
      sgst: Paise.rupees(sgst),
      total: Paise.rupees(tot),
      round_off: Paise.rupees(payable - tot),
      payable: Paise.rupees(payable),
      paid: Paise.rupees(paid),
      remaining: Paise.rupees(remaining),
      subtotal_cents: sub,
      discount_cents: disc,
      charges_cents: chg,
      taxable_cents: taxable,
      cgst_cents: cgst,
      sgst_cents: sgst,
      total_cents: tot,
      round_off_cents: payable - tot,
      payable_cents: payable,
      paid_cents: paid,
      remaining_cents: remaining
    }
  end

  # Freeze the tax amounts on the row so the stored figures match the invoice.
  def store_tax_cents!
    update_columns(cgst_cents: cgst_amount_cents, sgst_cents: sgst_amount_cents)
  end

  def total_net_grams
    line_items.to_a.sum(BigDecimal('0'), &:net_grams_total)
  end

  def total_gross_grams
    line_items.to_a.sum(BigDecimal('0'), &:gross_grams_total)
  end

  def ensure_share_token!
    return share_token if share_token.present?

    assign_share_token
    update_column(:share_token, share_token) if persisted?
    share_token
  end

  def self.next_invoice_number(date)
    prefix = "INV-#{date.strftime('%Y%m%d')}-"
    last = where('invoice_number LIKE ?', "#{prefix}%").pluck(:invoice_number)
                                                       .map { |n| n.delete_prefix(prefix).to_i }
                                                       .max.to_i
    "#{prefix}#{(last + 1).to_s.rjust(3, '0')}"
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
    self.invoice_number ||= self.class.next_invoice_number(sale_date)
  end

  def decrement_inventory_on_payment
    return unless status == 'paid'
    return if respond_to?(:stock_decremented_at) && stock_decremented_at.present?

    Order.transaction do
      line_items.each do |li|
        ji = li.jewelry_item
        unless ji
          Rails.logger.warn "Order##{id} line_item #{li.id} has no associated jewelry_item"
          next
        end

        qty = li.quantity.to_i
        # Atomic update; CASE keeps the tray from going below zero on every adapter.
        JewelryItem.where(id: ji.id).update_all(['quantity = CASE WHEN quantity - ? < 0 THEN 0 ELSE quantity - ? END', qty, qty])
      end

      update_column(:stock_decremented_at, Time.zone.now) if respond_to?(:stock_decremented_at)
    end
  end
end
