class OrdersController < ApplicationController
  protect_from_forgery with: :exception

  def index
    @q = params[:q].to_s.strip
    eager = [:customer, :payments, { line_items: :jewelry_item }]

    if @q.present?
      q = @q.strip
      parsed_date = nil
      begin
        parsed_date = Date.parse(q) if q =~ /\A\d{4}-\d{2}-\d{2}\z/
      rescue ArgumentError
        parsed_date = nil
      end

      orders = Order.left_joins(:customer, line_items: :jewelry_item).distinct
      clauses = []
      args = {}
      args[:qtxt] = "%#{q.downcase}%"

      if q =~ /\A\d+\z/
        clauses << 'orders.id = :oid'
        args[:oid] = q.to_i
      end

      if Order::STATUSES.map(&:downcase).include?(q.downcase)
        clauses << 'lower(orders.status) = :status'
        args[:status] = q.downcase
      end

      if parsed_date
        clauses << 'orders.created_at BETWEEN :dstart AND :dend'
        args[:dstart] = parsed_date.beginning_of_day
        args[:dend] = parsed_date.end_of_day
      end

      clauses << 'lower(jewelry_items.name) LIKE :qtxt'
      clauses << 'lower(orders.invoice_number) LIKE :qtxt'
      clauses << 'lower(customers.first_name) LIKE :qtxt'
      clauses << 'lower(customers.last_name) LIKE :qtxt'

      @orders = orders.where(clauses.join(' OR '), args).includes(eager).order(created_at: :desc)
    else
      @orders = Order.includes(eager).order(created_at: :desc)
    end

    paid_today = Order.where(status: 'paid', sale_date: Time.zone.today)
                      .includes(:line_items, :payments)
    @today_total = Paise.rupees(paid_today.sum(&:total_cents))
    render template: 'orders/index'
  end

  def show
    load_order
  end

  # POST /orders/:id/record_payment
  def record_payment
    load_order
    if @order.status != 'pending'
      redirect_to @order, alert: 'This bill is already settled.'
      return
    end

    pm = params[:payment_method].to_s.strip
    pay = Paise.dec(params[:payment_amount])
    discount = params[:discount].present? ? Paise.dec(params[:discount]) : Paise.dec!(@order.discount)
    charges = params[:charges].present? ? Paise.dec(params[:charges]) : Paise.dec!(@order.charges)
    cgst_rate = params[:cgst_rate].present? ? Paise.dec(params[:cgst_rate]) : @order.cgst_rate_or_default
    sgst_rate = params[:sgst_rate].present? ? Paise.dec(params[:sgst_rate]) : @order.sgst_rate_or_default

    failure = nil
    Payment.transaction do
      # Row lock: a second receipt on the same bill waits here, then sees the first.
      @order.lock!
      if @order.status != 'pending'
        failure = :settled
        raise ActiveRecord::Rollback
      end

      @order.assign_attributes(
        discount: discount && Paise.round2(discount),
        charges: charges && Paise.round2(charges),
        cgst_rate: cgst_rate && Paise.round2(cgst_rate),
        sgst_rate: sgst_rate && Paise.round2(sgst_rate)
      )
      @order.payment_method = pm if @order.respond_to?(:payment_method=)

      pay_cents = pay ? Paise.from_rupees(pay) : nil
      check_payment_terms!(pm, pay_cents, [pay, discount, charges, cgst_rate, sgst_rate])
      if @order.errors.any?
        failure = :invalid
        raise ActiveRecord::Rollback
      end

      @order.save!
      @order.store_tax_cents!
      payment = Payment.create!(order_id: @order.id, customer_id: @order.customer_id, amount_cents: pay_cents, payment_method: pm)
      payment.update_columns(receipt_number: "RCT-#{Time.zone.today.strftime('%Y%m%d')}-#{payment.id.to_s.rjust(4, '0')}")
      @order.payments.reset
      @order.update!(status: (@order.remaining_cents.zero? ? 'paid' : 'pending'))
      @order.customer&.recompute_balance!
    end

    case failure
    when :settled
      redirect_to @order, alert: 'This bill is already settled.'
    when :invalid
      render :show, status: :unprocessable_entity
    else
      if @order.status == 'paid'
        redirect_to invoice_order_path(@order)
      else
        redirect_to @order, notice: 'Partial payment recorded. Receipt is in the payments list.'
      end
    end
  end

  def invoice
    load_order
    prepare_invoice(public_view: false)
    render template: 'orders/invoice', layout: false
  end

  def shared_invoice
    token = params[:token].to_s
    raise ActiveRecord::RecordNotFound if token.blank?

    @order = Order.includes(:customer, :payments, line_items: { jewelry_item: [:metal, :purity, :jewellery_category] })
                  .find_by!(share_token: token)
    prepare_invoice(public_view: true)
    render template: 'orders/invoice', layout: false
  end

  def new
    load_bill_form
    @order = Order.new(
      status: 'pending',
      cgst_rate: Order::DEFAULT_CGST_RATE,
      sgst_rate: Order::DEFAULT_SGST_RATE,
      discount: 0,
      charges: 0
    )
    @customer_mode = 'existing'
    @selected_customer_id = params[:customer_id].presence
    @draft_customer = Customer.new
    @draft_lines = []
  end

  def create
    load_bill_form
    @customer_mode = params[:customer_mode].to_s == 'new' ? 'new' : 'existing'
    @selected_customer_id = params[:existing_customer_id].presence
    @draft_customer = Customer.new(customer_params)
    @draft_lines = raw_line_item_params
    @order = Order.new(status: 'pending')
    assign_bill_totals(@order)

    saved = raise_bill_safely

    if saved
      redirect_to saved, notice: 'Bill raised. Record payment when the client settles.'
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def load_order
    @order = Order.includes(:customer, :payments, line_items: { jewelry_item: [:metal, :purity, :jewellery_category] }).find(params[:id])
  end

  def prepare_invoice(public_view:)
    @public_invoice = public_view
    @shop = current_user.try(:shop_profile) unless public_view
    @shop ||= ShopProfile.first if defined?(ShopProfile)
    token = @order.ensure_share_token!
    @qr_payload = shared_invoice_url(token)
  end

  def load_bill_form
    @items = JewelryItem.available_for_sale.includes(:metal, :purity, :jewellery_category).order(:name)
    @customers = Customer.order(:first_name, :last_name).limit(300)
  end

  def customer_params
    return {} unless params[:customer].present?

    params.require(:customer).permit(:first_name, :last_name, :address, :aadhaar_or_pan, :gst_number, :email, :phone)
  end

  def raw_line_item_params
    raw = params[:line_items]
    rows = if raw.is_a?(Array)
             raw
           elsif raw.respond_to?(:to_unsafe_h)
             raw.to_unsafe_h.values
           elsif raw.respond_to?(:values)
             raw.values
           else
             []
           end
    rows.map do |row|
      row = row.permit(:jewelry_item_id, :quantity, :gross_weight, :net_weight, :rate_per_gram, :making_charge_percent, :additional_charge, :hsn, :huid) if row.respond_to?(:permit)
      row.to_h
    end
  end

  # Column limits: line_items amounts decimal(12,2), weights decimal(10,2),
  # orders discount/charges decimal(10,2).
  MAX_LINE_RUPEES = BigDecimal('9999999999.99')
  MAX_GRAMS = BigDecimal('99999999.99')
  MAX_BILL_RUPEES = BigDecimal('99999999.99')
  MAX_TAX_RATE = BigDecimal('20')

  def assign_bill_totals(order)
    inputs = {
      discount: params[:discount].present? ? Paise.dec(params[:discount]) : BigDecimal('0'),
      charges: params[:charges].present? ? Paise.dec(params[:charges]) : BigDecimal('0'),
      cgst_rate: params[:cgst_rate].present? ? Paise.dec(params[:cgst_rate]) : BigDecimal(Order::DEFAULT_CGST_RATE.to_s),
      sgst_rate: params[:sgst_rate].present? ? Paise.dec(params[:sgst_rate]) : BigDecimal(Order::DEFAULT_SGST_RATE.to_s)
    }
    @bill_inputs_invalid = inputs.values.any?(&:nil?)
    inputs.each { |key, value| order[key] = Paise.round2(value) }
  end

  def whole_number(value)
    str = value.to_s.strip
    str.match?(/\A\d+\z/) ? str.to_i : nil
  end

  def parsed_line_items
    raw_line_item_params.filter_map do |row|
      raw = row.to_h.with_indifferent_access
      next if raw.values.all?(&:blank?)
      next if raw[:jewelry_item_id].blank?

      item = JewelryItem.includes(:metal, :purity).find_by(id: raw[:jewelry_item_id])
      qty = whole_number(raw[:quantity])
      net = Paise.dec(raw[:net_weight])
      gross = raw[:gross_weight].present? ? Paise.dec(raw[:gross_weight]) : net
      rate = Paise.dec(raw[:rate_per_gram])
      making_pct = raw[:making_charge_percent].present? ? Paise.dec(raw[:making_charge_percent]) : BigDecimal('0')
      additional = raw[:additional_charge].present? ? Paise.dec(raw[:additional_charge]) : BigDecimal('0')
      numbers_ok = [qty, net, gross, rate, making_pct, additional].none?(&:nil?)

      qty ||= 0
      net = Paise.round2(net)
      gross = Paise.round2(gross)
      rate = Paise.round2(rate)
      additional = Paise.round2(additional)
      making_pct = Paise.dec!(making_pct)
      metal = (rate * net * qty).round(2, BigDecimal::ROUND_HALF_UP)
      making = (metal * making_pct / 100).round(2, BigDecimal::ROUND_HALF_UP)
      {
        item: item,
        numbers_ok: numbers_ok,
        quantity: qty,
        net_weight: net,
        gross_weight: gross,
        rate_per_gram: rate,
        making_percent: making_pct,
        making_charge: making,
        additional_charge: additional,
        metal_amount: metal,
        hsn: raw[:hsn].presence || item&.invoice_hsn,
        huid: raw[:huid].presence || item&.sku
      }
    end
  end

  def line_cents(line)
    Paise.from_rupees(line[:metal_amount]) + Paise.from_rupees(line[:making_charge]) +
      Paise.from_rupees(line[:additional_charge]) * line[:quantity]
  end

  # Discount, extra charges and tax rates on @order. The discount is capped at
  # the amount it comes off: the total after CGST + SGST (subtotal on old bills).
  def check_bill_amounts!(subtotal_cents)
    disc = Paise.dec!(@order.discount)
    chg = Paise.dec!(@order.charges)
    @order.errors.add(:base, 'Discount cannot be negative.') if disc.negative?
    @order.errors.add(:base, 'Extra charges cannot be negative.') if chg.negative?
    if disc > MAX_BILL_RUPEES || chg > MAX_BILL_RUPEES
      @order.errors.add(:base, 'Discount and extra charges must each stay below ₹10 crore.')
    end
    [['CGST', @order.cgst_rate], ['SGST', @order.sgst_rate]].each do |label, rate|
      r = Paise.dec!(rate)
      @order.errors.add(:base, "#{label} cannot be negative.") if r.negative?
      @order.errors.add(:base, "#{label} cannot exceed #{MAX_TAX_RATE.to_i}%.") if r > MAX_TAX_RATE
    end
    return if @order.errors.any?

    if @order.discount_after_tax?
      cap = subtotal_cents + Paise.percent_of(subtotal_cents, @order.cgst_rate_or_default) +
            Paise.percent_of(subtotal_cents, @order.sgst_rate_or_default)
      label = 'the bill total after tax'
    else
      cap = subtotal_cents
      label = 'the bill subtotal'
    end
    if Paise.from_rupees(disc) > cap
      @order.errors.add(:base, "Discount cannot exceed #{label} (₹#{'%.2f' % Paise.rupees(cap)}).")
    end
  end

  def check_payment_terms!(pm, pay_cents, raw_values)
    if raw_values.any?(&:nil?)
      @order.errors.add(:base, 'Payment, discount, charges and tax rates must be plain numbers.')
      return
    end
    @order.errors.add(:payment_method, 'must be selected') if pm.blank?
    check_bill_amounts!(@order.subtotal_cents)
    return if @order.errors.any?

    payable = @order.payable_cents
    paid = @order.paid_cents
    if payable < paid
      @order.errors.add(:base, "These terms bring the bill to ₹#{Paise.rupees(payable).to_i}, below the ₹#{'%.2f' % Paise.rupees(paid)} already received. Reduce the discount.")
      return
    end

    due = @order.remaining_cents
    if pay_cents <= 0
      @order.errors.add(:base, 'Payment amount must be greater than 0.')
    elsif pay_cents % 100 != 0
      @order.errors.add(:base, 'Pay in whole rupees; the bill is rounded off to the rupee.')
    elsif pay_cents > due
      @order.errors.add(:base, "Payment cannot exceed the remaining due of ₹#{Paise.rupees(due).to_i}.")
    end
  end

  def resolve_customer
    if @customer_mode == 'new'
      attrs = customer_params
      first = attrs[:first_name].to_s.strip
      digits = attrs[:phone].to_s.gsub(/\D/, '')
      @order.errors.add(:base, 'Give the client a first name.') if first.blank?
      @order.errors.add(:base, 'Phone must be exactly 10 digits.') if digits.length != 10
      return nil if @order.errors.any?

      found = Customer.find_by_phone_loose(attrs[:phone])
      found ||= Customer.find_by(email: attrs[:email].to_s.strip.downcase) if attrs[:email].present?
      return found if found

      customer = Customer.new(attrs.merge(phone: digits))
      @draft_customer = customer
      unless customer.valid?
        @order.errors.add(:base, customer.errors.full_messages.to_sentence)
        return nil
      end
      customer
    else
      unless @selected_customer_id.present?
        @order.errors.add(:base, 'Choose a client on the book, or register a new one.')
        return nil
      end
      customer = Customer.find_by(id: @selected_customer_id)
      @order.errors.add(:base, 'That client could not be found.') unless customer
      customer
    end
  end

  def validate_bill!(lines)
    if lines.empty?
      @order.errors.add(:base, 'Add at least one catalogue piece to the bill.')
    end

    @order.errors.add(:base, 'Discount, extra charges and tax rates must be plain numbers.') if @bill_inputs_invalid

    qty_by_item = Hash.new(0)
    lines.each do |line|
      qty_by_item[line[:item].id] += line[:quantity].to_i if line[:item] && line[:numbers_ok]
    end
    over_stock = []
    lines.each_with_index do |line, index|
      n = index + 1
      unless line[:item]
        @order.errors.add(:base, "Piece #{n}: choose a catalogue piece.")
        next
      end
      unless line[:numbers_ok]
        @order.errors.add(:base, "Piece #{n}: quantity, weights, rate and charges must be plain numbers.")
        next
      end
      if line[:net_weight] > MAX_GRAMS || line[:gross_weight] > MAX_GRAMS
        @order.errors.add(:base, "Piece #{n}: weight is larger than a bill line can hold.")
      end
      if [line[:metal_amount], line[:making_charge], line[:additional_charge] * line[:quantity]].any? { |v| v > MAX_LINE_RUPEES }
        @order.errors.add(:base, "Piece #{n}: amount is larger than a bill line can hold.")
      end
      name = line[:item].name
      stock = line[:item].quantity.to_i
      if line[:quantity] < 1
        @order.errors.add(:base, "Piece #{n}: quantity must be at least 1.")
      elsif line[:quantity] > stock
        @order.errors.add(:base, "Piece #{n}: qty cannot exceed the #{stock} pcs remaining of #{name}.")
      elsif qty_by_item[line[:item].id] > stock && !over_stock.include?(line[:item].id)
        over_stock << line[:item].id
        @order.errors.add(:base, "#{name} is on this bill #{qty_by_item[line[:item].id]} times in total, but only #{stock} pcs remain.")
      end
      unless line[:item].sellable?
        if line[:item].archived?
          @order.errors.add(:base, "Piece #{n}: #{name} is archived and cannot be sold until it is restored.")
        else
          locked = line[:item].metal&.rate_board_locked? ? line[:item].metal.name : 'this hallmark'
          @order.errors.add(:base, "Piece #{n}: #{name} cannot be sold while #{locked} is inactive.")
        end
      end
      @order.errors.add(:base, "Piece #{n}: net weight must be greater than 0 g.") if line[:net_weight] <= 0
      @order.errors.add(:base, "Piece #{n}: gross weight cannot be less than net weight.") if line[:gross_weight] < line[:net_weight]
      @order.errors.add(:base, "Piece #{n}: set a rupee-per-gram rate.") if line[:rate_per_gram] <= 0
      @order.errors.add(:base, "Piece #{n}: making cannot be negative.") if line[:making_percent] < 0
      @order.errors.add(:base, "Piece #{n}: additional charge cannot be negative.") if line[:additional_charge] < 0
    end

    return if @bill_inputs_invalid

    check_bill_amounts!(lines.select { |l| l[:numbers_ok] }.sum { |l| line_cents(l) })
  end

  def raise_bill_safely
    attempts = 0
    begin
      attempts += 1
      raise_bill!
    rescue ActiveRecord::RecordInvalid => e
      @order.errors.add(:base, e.record.errors.full_messages.to_sentence)
      nil
    rescue ActiveRecord::RecordNotUnique => e
      clash = e.message.include?('invoice_number')
      retry if clash && attempts < 4
      @order.errors.add(:base, clash ? 'Another bill took this invoice number at the same moment. Please submit again.' : 'That phone or email is already on the book. Choose the existing client.')
      nil
    end
  end

  def raise_bill!
    lines = parsed_line_items
    customer = resolve_customer
    validate_bill!(lines)
    return nil if @order.errors.any? || customer.nil?

    Order.transaction do
      customer.save! if customer.new_record?
      order = Order.new(
        status: 'pending',
        customer: customer,
        discount: @order.discount,
        charges: @order.charges,
        cgst_rate: @order.cgst_rate,
        sgst_rate: @order.sgst_rate,
        gross_weight: lines.sum(BigDecimal('0')) { |l| l[:gross_weight] * l[:quantity] },
        net_weight: lines.sum(BigDecimal('0')) { |l| l[:net_weight] * l[:quantity] }
      )
      order.save!

      lines.each do |line|
        order.line_items.create!(
          jewelry_item: line[:item],
          price_cents: Paise.from_rupees(line[:rate_per_gram] * line[:net_weight]),
          quantity: line[:quantity],
          weight: line[:net_weight],
          gross_weight: line[:gross_weight],
          net_weight: line[:net_weight],
          making_charge: line[:making_charge],
          additional_charge: line[:additional_charge],
          hsn: line[:hsn],
          huid: line[:huid],
          rate: line[:metal_amount]
        )
      end

      order.line_items.reset
      order.store_tax_cents!
      customer.recompute_balance!
      order
    end
  end
end
