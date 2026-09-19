class LedgersController < ApplicationController
  def index
    @q = params[:q].to_s.strip
    @status = %w[all due advance settled].include?(params[:status].to_s) ? params[:status].to_s : 'all'

    scope = Customer.includes(:ledger_entries, :payments, orders: [:line_items, :payments]).order(:first_name, :last_name)
    if @q.present?
      like = "%#{@q.downcase}%"
      scope = scope.where(
        "LOWER(customers.first_name) LIKE :q OR LOWER(COALESCE(customers.last_name, '')) LIKE :q OR LOWER(customers.phone) LIKE :q OR LOWER(COALESCE(customers.email, '')) LIKE :q",
        q: like
      )
    else
      active_ids = Order.where.not(customer_id: nil).distinct.pluck(:customer_id) +
                   LedgerEntry.distinct.pluck(:customer_id) +
                   Customer.where.not(balance_cents: 0).pluck(:id)
      scope = active_ids.any? ? scope.where(id: active_ids.uniq) : scope.none
    end

    rows = scope.limit(200).to_a.map { |customer| decorate(customer) }
    @status_counts = {
      'all' => rows.size,
      'due' => rows.count { |row| row[:cents].positive? },
      'advance' => rows.count { |row| row[:cents].negative? },
      'settled' => rows.count { |row| row[:cents].zero? }
    }
    @khatas = case @status
              when 'due' then rows.select { |row| row[:cents].positive? }
              when 'advance' then rows.select { |row| row[:cents].negative? }
              when 'settled' then rows.select { |row| row[:cents].zero? }
              else rows
              end

    @receivable = rows.select { |row| row[:cents].positive? }.sum { |row| row[:cents] } / 100.0
    @advances = rows.select { |row| row[:cents].negative? }.sum { |row| -row[:cents] } / 100.0
    @house_count = rows.size
  end

  def show
    load_khata
  end

  def new
    @entry = LedgerEntry.new(entry_date: Time.zone.today, kind: 'opening')
    @entry.customer_id = params[:customer_id] if params[:customer_id].present?
    load_form
  end

  def create
    @entry = LedgerEntry.new(entry_params)
    if @entry.save
      @entry.customer.recompute_balance! if @entry.customer.respond_to?(:recompute_balance!)
      redirect_to ledger_path(@entry.customer), notice: "Posted on #{@entry.customer.full_name}'s khata."
    else
      load_form
      render :new
    end
  end

  private

  def entry_params
    params.require(:ledger_entry).permit(:customer_id, :entry_date, :kind, :amount, :amount_cents, :note)
  end

  def load_form
    @customers = Customer.order(:first_name, :last_name)
    @customers_payload = @customers.map do |customer|
      {
        id: customer.id,
        name: customer.full_name,
        phone: customer.phone.to_s,
        outstanding: customer.outstanding.to_f
      }
    end
  end

  def load_khata
    @customer = Customer.includes(:ledger_entries, :payments, orders: [:line_items, :payments]).find(params[:id])
    @from = parse_date(params[:from])
    @to = parse_date(params[:to])
    @lines = window_statement(statement_for(@customer), @from, @to)
    @cents = @customer.live_outstanding_cents
  end

  def decorate(customer)
    cents = customer.live_outstanding_cents
    last_bill = customer.orders.max_by { |order| order.try(:sale_date) || order.created_at.to_date }
    last_pay = customer.payments.max_by(&:created_at)
    {
      customer: customer,
      cents: cents,
      amount: cents / 100.0,
      bills: customer.orders.size,
      last_bill: last_bill ? (last_bill.try(:sale_date) || last_bill.created_at.to_date) : nil,
      last_pay: last_pay&.created_at
    }
  end

  def statement_for(customer)
    bills = customer.orders.index_by(&:id)
    lines = []

    customer.orders.each do |order|
      next if %w[cancelled failed].include?(order.status.to_s)
      at = stamp(order.created_at, order.try(:sale_date))
      lines << {
        occurred: at.to_date,
        occurred_at: at,
        rank: 2,
        id: order.id,
        kind: 'bill',
        label: 'Bill',
        note: [order.invoice_number.presence || "Bill ##{order.id}", order.status].compact.join(' · '),
        debit: order.bill_breakdown[:total].to_f,
        credit: 0.0,
        href: order_path(order)
      }
    end

    customer.payments.each do |payment|
      at = stamp(payment.created_at)
      bill = bills[payment.order_id]
      ref = payment.try(:receipt_number).presence || "Receipt ##{payment.id}"
      against = bill&.invoice_number.presence || (payment.order_id ? "Bill ##{payment.order_id}" : nil)
      lines << {
        occurred: at.to_date,
        occurred_at: at,
        rank: 3,
        id: payment.id,
        kind: 'receipt',
        label: 'Receipt',
        note: [ref, payment.payment_method.presence, against].compact.join(' · '),
        debit: 0.0,
        credit: payment.amount,
        href: payment.order_id ? order_path(payment.order_id) : nil
      }
    end

    customer.ledger_entries.each do |entry|
      at = stamp(entry.created_at, entry.entry_date)
      lines << {
        occurred: entry.entry_date || at.to_date,
        occurred_at: at,
        rank: entry.credit? ? 4 : (entry.kind.to_s == 'opening' ? 0 : 1),
        id: entry.id,
        kind: entry.kind,
        label: entry.kind_label,
        note: entry.note.presence || entry.kind_label,
        debit: entry.debit_amount,
        credit: entry.credit_amount,
        href: nil
      }
    end

    running = 0.0
    lines.sort_by { |line| [line[:occurred_at].to_f, line[:rank].to_i, line[:id].to_i] }.map do |line|
      running += line[:debit].to_f - line[:credit].to_f
      line.merge(balance: running.round(2))
    end
  end

  def window_statement(lines, from, to)
    return number_lines(lines) if from.nil? && to.nil?

    prior = []
    kept = []
    lines.each do |line|
      date = line[:occurred]
      if from && date < from
        prior << line
      elsif to && date > to
        next
      else
        kept << line
      end
    end

    if from
      brought = prior.last ? prior.last[:balance].to_f : 0.0
      kept.unshift(
        occurred: from,
        occurred_at: from.in_time_zone.beginning_of_day,
        kind: 'brought',
        label: 'Brought forward',
        note: 'Balance before this window',
        debit: 0.0,
        credit: 0.0,
        balance: brought.round(2),
        href: nil
      )
    end
    number_lines(kept)
  end

  def number_lines(lines)
    lines.each_with_index.map { |line, index| line.merge(no: index + 1) }
  end

  def stamp(time, date = nil)
    return time.in_time_zone if time.present?
    return date.in_time_zone.beginning_of_day if date.present?
    Time.zone.now
  end

  def parse_date(value)
    return nil if value.blank?
    Date.parse(value.to_s)
  rescue ArgumentError
    nil
  end
end
