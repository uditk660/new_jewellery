class OrdersController < ApplicationController
  protect_from_forgery with: :exception

  def index
    @q = params[:q].to_s.strip
    if @q.present?
      q = @q.strip
      parsed_date = nil
      begin
        parsed_date = Date.parse(q) if q =~ /\A\d{4}-\d{2}-\d{2}\z/
      rescue ArgumentError
        parsed_date = nil
      end

      orders = Order.left_joins(line_items: :jewelry_item).distinct

      clauses = []
      args = {}

      # order id exact match when numeric
      if q =~ /\A\d+\z/
        clauses << 'orders.id = :oid'
        args[:oid] = q.to_i
      end

      # status exact match
      if Order::STATUSES.map(&:downcase).include?(q.downcase)
        clauses << 'lower(orders.status) = :status'
        args[:status] = q.downcase
      end

      # date exact match (YYYY-MM-DD)
      if parsed_date
        clauses << 'orders.created_at BETWEEN :dstart AND :dend'
        args[:dstart] = parsed_date.beginning_of_day
        args[:dend] = parsed_date.end_of_day
      end

      # item name partial match (case-insensitive)
      clauses << 'lower(jewelry_items.name) LIKE :iname'
      args[:iname] = "%#{q.downcase}%"

      @orders = orders.where(clauses.join(' OR '), args).order(created_at: :desc)
    else
      @orders = Order.order(created_at: :desc)
    end

    # total sales today (paid orders)
    # use Time.zone.today and the order's sale_date (set at creation) to avoid created_at timezone mismatches
    today = Time.zone.today
    paid_today = Order.where(status: 'paid', sale_date: today)
    # sum using the model helper to include taxes (uses stored cgst/igst cents if present)
    @today_total = paid_today.to_a.sum do |o|
      # prefer stored cents if available, else compute using rates
      if o.respond_to?(:cgst_cents) && o.respond_to?(:igst_cents)
        cents = o.subtotal_cents - (o.discount.to_f * 100).to_i + (o.charges.to_f * 100).to_i + (o.cgst_cents.to_i) + (o.igst_cents.to_i)
        cents.to_f / 100.0
      else
        o.total_with_taxes(cgst_rate: o.cgst_rate.to_f, igst_rate: o.igst_rate.to_f)
      end
    end
    render template: 'orders/index'
  end

  def show
    @order = Order.find(params[:id])
    render template: 'orders/show'
  end

  # POST /orders/:id/record_payment
  def record_payment
    @order = Order.find(params[:id])
    # accept either rates or explicit cents
    cgst_rate = params[:cgst_rate].to_f
    igst_rate = params[:igst_rate].to_f
    update_attrs = { discount: params[:discount].to_f, charges: params[:charges].to_f, cgst_rate: cgst_rate, igst_rate: igst_rate }
    pm = params[:payment_method].to_s
    if @order.respond_to?(:payment_method=)
      if pm.blank?
        @order.errors.add(:payment_method, 'must be selected')
        @order.assign_attributes(update_attrs)
        return render :show
      end
      update_attrs[:payment_method] = pm
    end

    @order.update(update_attrs)
    # compute and persist tax cents (use provided rates)
    @order.update_columns(cgst_cents: @order.cgst_amount_cents(cgst_rate), igst_cents: @order.igst_amount_cents(igst_rate))

    # parse payment amount
    pay_amt = (params[:payment_amount].to_f || 0.0)
    if pay_amt <= 0
      @order.errors.add(:base, 'Payment amount must be greater than 0')
      return render :show
    end

    # compute remaining before adding this payment
    remaining_cents = @order.remaining_cents.to_i
    pay_cents = (pay_amt * 100).to_i
    if pay_cents > remaining_cents
      @order.errors.add(:base, "Payment cannot exceed remaining amount (₹#{'%.2f' % (remaining_cents.to_f/100.0)})")
      return render :show
    end

    Payment.transaction do
      p = Payment.create!(order_id: @order.id, customer_id: @order.customer_id, amount_cents: pay_cents, payment_method: pm)
      # generate a receipt number and persist it on the payment (unique)
      rn = "RCT-#{Time.zone.today.strftime('%Y%m%d')}-#{p.id.to_s.rjust(4,'0')}"
      p.update_columns(receipt_number: rn)
      # decide if fully paid
      paid = @order.payments.sum(:amount_cents).to_i
      total = @order.total_cents_with_taxes(cgst_rate: (@order.cgst_rate || @order.cgst_rate_or_default), igst_rate: (@order.igst_rate || @order.igst_rate_or_default))
      # If stored cgst_cents/igst_cents present, prefer order.total_cents_with_taxes_cached
      total = @order.total_cents_with_taxes_cached if @order.respond_to?(:total_cents_with_taxes_cached)

      if paid >= total
        @order.update(status: 'paid')
      else
        # leave as pending (partial payment recorded)
        @order.update(status: 'pending')
      end

      # recompute customer outstanding balance
      if @order.customer
        @order.customer.recompute_balance!
      end
    end

    # redirect: if fully paid, show invoice; otherwise back to order with notice
    if @order.status == 'paid'
      redirect_to invoice_order_path(@order)
    else
      redirect_to @order, notice: 'Partial payment recorded. Receipt generated and linked in payments history.'
    end
  end

  def invoice
    @order = Order.find(params[:id])
  render template: 'orders/invoice', layout: 'application'
  end

  def new
    load_bill_form
    @order = Order.new(
      status: 'pending',
      cgst_rate: Order::DEFAULT_CGST_RATE,
      igst_rate: Order::DEFAULT_IGST_RATE,
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

    saved = nil
    begin
      saved = raise_bill!
    rescue ActiveRecord::RecordInvalid => e
      @order.errors.add(:base, e.record.errors.full_messages.to_sentence)
    rescue ActiveRecord::RecordNotUnique
      @order.errors.add(:base, 'That phone or email is already on the book. Choose the existing client.')
    end

    if saved
      redirect_to saved, notice: 'Bill raised. Record payment when the client settles.'
    else
      render :new
    end
  end

  private

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

  def assign_bill_totals(order)
    order.discount = params[:discount].to_f
    order.charges = params[:charges].to_f
    order.cgst_rate = params[:cgst_rate].present? ? params[:cgst_rate].to_f : Order::DEFAULT_CGST_RATE
    order.igst_rate = params[:igst_rate].present? ? params[:igst_rate].to_f : Order::DEFAULT_IGST_RATE
  end

  def parsed_line_items
    raw_line_item_params.filter_map do |raw|
      next if raw.values.all? { |v| v.blank? }

      item = JewelryItem.find_by(id: raw['jewelry_item_id'] || raw[:jewelry_item_id])
      qty = (raw['quantity'] || raw[:quantity]).to_i
      net = (raw['net_weight'] || raw[:net_weight]).to_f
      gross_raw = raw['gross_weight'] || raw[:gross_weight]
      gross = gross_raw.present? ? gross_raw.to_f : net
      rate = (raw['rate_per_gram'] || raw[:rate_per_gram]).to_f
      making_pct = (raw['making_charge_percent'] || raw[:making_charge_percent]).to_f
      additional = (raw['additional_charge'] || raw[:additional_charge]).to_f
      metal = (rate * net * qty).round(2)
      making = (metal * making_pct / 100.0).round(2)
      {
        item: item,
        quantity: qty,
        net_weight: net,
        gross_weight: gross,
        rate_per_gram: rate,
        making_percent: making_pct,
        making_charge: making,
        additional_charge: additional,
        metal_amount: metal,
        hsn: (raw['hsn'] || raw[:hsn]).presence || item&.invoice_hsn,
        huid: (raw['huid'] || raw[:huid]).presence || item&.sku
      }
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

    seen = []
    lines.each_with_index do |line, index|
      n = index + 1
      unless line[:item]
        @order.errors.add(:base, "Piece #{n}: choose a catalogue piece.")
        next
      end
      name = line[:item].name
      if seen.include?(line[:item].id)
        @order.errors.add(:base, "#{name} is already on this bill.")
      end
      seen << line[:item].id
      if line[:quantity] < 1
        @order.errors.add(:base, "Piece #{n}: quantity must be at least 1.")
      elsif line[:quantity] > line[:item].quantity.to_i
        @order.errors.add(:base, "Piece #{n}: qty cannot exceed the #{line[:item].quantity.to_i} pcs remaining of #{name}.")
      end
      @order.errors.add(:base, "Piece #{n}: net weight must be greater than 0 g.") if line[:net_weight] <= 0
      @order.errors.add(:base, "Piece #{n}: gross weight cannot be less than net weight.") if line[:gross_weight] < line[:net_weight]
      @order.errors.add(:base, "Piece #{n}: set a rupee-per-gram rate.") if line[:rate_per_gram] <= 0
      @order.errors.add(:base, "Piece #{n}: making cannot be negative.") if line[:making_percent] < 0
      @order.errors.add(:base, "Piece #{n}: additional charge cannot be negative.") if line[:additional_charge] < 0
    end

    @order.errors.add(:base, 'Discount cannot be negative.') if @order.discount.to_f < 0
    @order.errors.add(:base, 'Extra charges cannot be negative.') if @order.charges.to_f < 0
    @order.errors.add(:base, 'Tax rates cannot be negative.') if @order.cgst_rate.to_f < 0 || @order.igst_rate.to_f < 0

    subtotal = lines.sum { |l| l[:metal_amount] + l[:making_charge] + (l[:additional_charge] * l[:quantity]) }
    if @order.discount.to_f > subtotal && subtotal >= 0
      @order.errors.add(:base, 'Discount cannot exceed the bill subtotal.')
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
        discount: @order.discount.to_f,
        charges: @order.charges.to_f,
        cgst_rate: @order.cgst_rate.to_f,
        igst_rate: @order.igst_rate.to_f,
        gross_weight: lines.sum { |l| l[:gross_weight] },
        net_weight: lines.sum { |l| l[:net_weight] }
      )
      order.save!

      lines.each do |line|
        order.line_items.create!(
          jewelry_item: line[:item],
          price_cents: (line[:rate_per_gram] * line[:net_weight] * 100).round,
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

      order.update_columns(
        cgst_cents: order.cgst_amount_cents(order.cgst_rate),
        igst_cents: order.igst_amount_cents(order.igst_rate)
      )
      customer.recompute_balance! if customer.respond_to?(:recompute_balance!)
      order
    end
  end
end
