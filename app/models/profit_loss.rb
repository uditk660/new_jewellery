# Accrual house result for a date window. Metal on the bill is board recovery;
# the house keeps making, extras and charges after discounts and cash refunds.
class ProfitLoss
  WINDOWS = %w[today yesterday week month year custom].freeze

  attr_reader :from, :to, :window, :metal_id, :return_records

  def self.for(params, returns: [])
    today = Time.zone.today
    window = WINDOWS.include?(params[:window].to_s) ? params[:window].to_s : 'month'
    from, to = range_for(window, params, today)
    from, to = to, from if from > to
    new(
      from: from,
      to: to,
      window: window,
      metal_id: params[:metal_id].presence,
      returns: returns
    )
  end

  def self.range_for(window, params, today = Time.zone.today)
    case window
    when 'today' then [today, today]
    when 'yesterday' then [today - 1, today - 1]
    when 'week' then [today.beginning_of_week, today.end_of_week]
    when 'year' then [today.beginning_of_year, today.end_of_year]
    when 'custom'
      parsed_from = parse_date(params[:from]) || today.beginning_of_month
      parsed_to = parse_date(params[:to]) || today
      [parsed_from, parsed_to]
    else
      [today.beginning_of_month, today.end_of_month]
    end
  end

  def self.parse_date(value)
    return value if value.is_a?(Date)
    Date.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end

  def initialize(from:, to:, window: 'month', metal_id: nil, returns: [])
    @from = from
    @to = to
    @window = window
    @metal_id = metal_id.presence
    @return_records = Array(returns)
  end

  def label
    case window
    when 'today' then "Today · #{from.strftime('%d %b %Y')}"
    when 'yesterday' then "Yesterday · #{from.strftime('%d %b %Y')}"
    when 'week' then "This week · #{from.strftime('%d %b')} – #{to.strftime('%d %b %Y')}"
    when 'month' then from.strftime('%B %Y')
    when 'year' then from.strftime('%Y')
    else "#{from.strftime('%d %b %Y')} – #{to.strftime('%d %b %Y')}"
    end
  end

  def metal_filter
    return nil if metal_id.blank?

    @metal_filter ||= Metal.find_by(id: metal_id)
  end

  def orders
    @orders ||= begin
      rel = Order.includes(:customer, :payments, line_items: { jewelry_item: [:metal, :purity, :jewellery_category] })
                 .where(sale_date: from..to)
                 .where.not(status: %w[cancelled failed])
                 .order(:sale_date, :id)
      rows = rel.to_a
      metal_id.present? ? rows.select { |order| slice(order)[:pcs].positive? } : rows
    end
  end

  def slices
    @slices ||= orders.map { |order| slice(order) }
  end

  def metal
    slices.sum { |row| row[:metal] }
  end

  def making
    slices.sum { |row| row[:making] }
  end

  def extra
    slices.sum { |row| row[:extra] }
  end

  def charges
    slices.sum { |row| row[:charges] }
  end

  def discount
    slices.sum { |row| row[:discount] }
  end

  def grams
    slices.sum { |row| row[:grams] }
  end

  def pieces
    slices.sum { |row| row[:pcs] }
  end

  def gst
    slices.sum { |row| row[:gst] }
  end

  def cgst
    slices.sum { |row| row[:cgst].to_f }
  end

  def sgst
    slices.sum { |row| row[:sgst].to_f }
  end

  def taxable
    slices.sum { |row| row[:taxable] }
  end

  def bill_total
    slices.sum { |row| row[:total] }
  end

  def house_result
    making + extra + charges - discount - cash_refunds
  end

  def cash_refunds
    return 0.0 if metal_id.present?

    @cash_refunds ||= return_records.sum do |record|
      row = record.respond_to?(:to_h) ? record.to_h.stringify_keys : {}
      next 0.0 unless row['action'].to_s == 'cash'

      at = parse_time(row['created_at'])
      next 0.0 unless at && at.to_date.between?(from, to)

      row['amount'].to_f
    end
  end

  def receipts
    @receipts ||= Payment.where(created_at: from.beginning_of_day..to.end_of_day).sum(:amount_cents).to_i / 100.0
  end

  def outstanding
    slices.sum { |row| row[:remaining] }
  end

  def paid_bills
    orders.count { |order| order.status == 'paid' }
  end

  def open_bills
    orders.count { |order| order.status != 'paid' }
  end

  def bill_count
    orders.size
  end

  def margin_percent
    taxable.positive? ? (house_result / taxable * 100.0) : 0.0
  end

  def mix
    parts = [
      { key: 'metal', label: 'Metal', amount: metal, tone: 'metal' },
      { key: 'making', label: 'Making', amount: making, tone: 'making' },
      { key: 'extra', label: 'Extras', amount: extra, tone: 'extra' },
      { key: 'charges', label: 'Charges', amount: charges, tone: 'charges' }
    ]
    base = parts.sum { |part| part[:amount] }
    parts.each do |part|
      part[:share] = base.positive? ? (part[:amount] / base * 100.0) : 0.0
    end
    parts
  end

  def by_metal
    groups = {}
    orders.each do |order|
      order.line_items.each do |item|
        metal_row = item.jewelry_item&.metal
        next if metal_id.present? && metal_row&.id.to_s != metal_id.to_s

        key = metal_row&.id || 0
        groups[key] ||= {
          id: key,
          name: metal_row&.name.presence || 'Unset metal',
          colour: metal_row&.chip_colour.presence || '#c9a227',
          grams: 0.0,
          pcs: 0,
          metal: 0.0,
          making: 0.0,
          extra: 0.0
        }
        groups[key][:grams] += item.net_weight.to_f * item.quantity.to_i
        groups[key][:pcs] += item.quantity.to_i
        groups[key][:metal] += item.metal_amount.to_f
        groups[key][:making] += item.making_charge.to_f
        groups[key][:extra] += item.additional_charge.to_f * item.quantity.to_i
      end
    end
    groups.values
          .map { |row| row.merge(house: row[:making] + row[:extra]) }
          .sort_by { |row| -row[:house] }
  end

  def bills
    slices.sort_by { |row| [row[:date], row[:id]] }.reverse
  end

  def series(key = :house)
    days = (from..to).to_a
    return [] if days.empty?

    grouped = slices.group_by { |row| row[:date] }
    if days.size > 45
      weeks = days.group_by { |day| day.beginning_of_week }
      weeks.map do |start, week_days|
        value = week_days.sum { |day| (grouped[day] || []).sum { |row| row[key].to_f } }
        { label: start.strftime('%d %b'), value: value, hint: "#{start.strftime('%d %b')} week" }
      end
    else
      days.map do |day|
        value = (grouped[day] || []).sum { |row| row[key].to_f }
        { label: day.strftime('%d'), value: value, hint: day.strftime('%d %b %Y') }
      end
    end
  end

  def series_max(key = :house)
    series(key).map { |point| point[:value] }.max.to_f
  end

  def statement_lines
    [
      { kind: 'plus', label: 'Metal at the board', amount: metal, note: "#{format('%.2f', grams)} g net · board ₹/g on the bill. This recovers metal; it is not house profit." },
      { kind: 'plus', label: 'Making', amount: making, note: 'Labour and house margin written on each piece.' },
      { kind: 'plus', label: 'Stones & extras', amount: extra, note: 'Per-piece extras × quantity.' },
      { kind: 'subtotal', label: 'Taxable on bills', amount: taxable, note: 'What CGST + SGST is computed on.' },
      { kind: 'pass', label: 'GST collected', amount: gst, note: 'Held for government. Not kept by the house.' },
      { kind: 'minus', label: 'Discounts given', amount: discount, note: 'Courtesy taken off the bill total after tax.' },
      { kind: 'plus', label: 'Bill charges', amount: charges, note: 'Any extra added on the total after tax, not on a line.' },
      { kind: 'subtotal', label: 'Bill total', amount: bill_total, note: "#{bill_count} #{bill_count == 1 ? 'invoice' : 'invoices'} · #{pieces} #{pieces == 1 ? 'piece' : 'pieces'}." },
      { kind: 'minus', label: 'Cash refunds', amount: cash_refunds, note: metal_id.present? ? 'Refunds stay on the full-house book when a metal is chosen.' : 'Cash returns taken in this window.' },
      { kind: 'result', label: 'House result', amount: house_result, note: 'Making, extras and charges after discounts and cash refunds.' }
    ]
  end

  private

  def slice(order)
    items = order.line_items.to_a
    items = items.select { |item| item.jewelry_item&.metal_id.to_s == metal_id.to_s } if metal_id.present?
    metal_amt = items.sum { |item| item.metal_amount.to_f }
    making_amt = items.sum { |item| item.making_charge.to_f }
    extra_amt = items.sum { |item| item.additional_charge.to_f * item.quantity.to_i }
    grams_amt = items.sum { |item| item.net_weight.to_f * item.quantity.to_i }
    pcs_amt = items.sum { |item| item.quantity.to_i }
    line_sub = items.sum { |item| item.line_amount.to_f }
    full_sub = order.line_items.to_a.sum { |item| item.line_amount.to_f }
    ratio = metal_id.present? && full_sub.positive? ? (line_sub / full_sub) : 1.0
    breakdown = order.bill_breakdown
    discount_amt = order.discount.to_f * ratio
    charges_amt = order.charges.to_f * ratio
    cgst_amt = breakdown[:cgst].to_f * ratio
    sgst_amt = breakdown[:sgst].to_f * ratio
    gst_amt = cgst_amt + sgst_amt
    house_amt = making_amt + extra_amt + charges_amt - discount_amt
    {
      id: order.id,
      order: order,
      invoice: order.invoice_number.presence || "Bill ##{order.id}",
      date: order.sale_date || order.created_at.to_date,
      client: order.customer,
      status: order.status,
      pcs: pcs_amt,
      grams: grams_amt,
      metal: metal_amt,
      making: making_amt,
      extra: extra_amt,
      charges: charges_amt,
      discount: discount_amt,
      cgst: cgst_amt,
      sgst: sgst_amt,
      gst: gst_amt,
      taxable: metal_amt + making_amt + extra_amt + (breakdown[:discount_after_tax] ? 0 : charges_amt - discount_amt),
      total: metal_amt + making_amt + extra_amt + charges_amt - discount_amt + gst_amt,
      house: house_amt,
      remaining: order.remaining_amount.to_f * ratio
    }
  end

  def parse_time(value)
    return value if value.respond_to?(:to_date)
    Time.zone.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end
end
