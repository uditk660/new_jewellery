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
    @today_total = paid_today.sum { |o| o.bill_breakdown[:total] }
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
    pay_amt = params[:payment_amount].to_f
    cgst_rate = params[:cgst_rate].present? ? params[:cgst_rate].to_f : @order.cgst_rate_or_default
    igst_rate = params[:igst_rate].present? ? params[:igst_rate].to_f : @order.igst_rate_or_default
    discount = params[:discount].to_f
    charges = params[:charges].present? ? params[:charges].to_f : @order.charges.to_f

    @order.assign_attributes(
      discount: discount,
      charges: charges,
      cgst_rate: cgst_rate,
      igst_rate: igst_rate
    )
    @order.payment_method = pm if @order.respond_to?(:payment_method=)

    if pm.blank?
      @order.errors.add(:payment_method, 'must be selected')
      return render :show
    end
    if discount.negative? || charges.negative? || cgst_rate.negative? || igst_rate.negative?
      @order.errors.add(:base, 'Discount, charges and tax cannot be negative.')
      return render :show
    end
    if discount > @order.bill_breakdown[:subtotal]
      @order.errors.add(:base, 'Discount cannot exceed the bill subtotal.')
      return render :show
    end
    if pay_amt <= 0
      @order.errors.add(:base, 'Payment amount must be greater than 0.')
      return render :show
    end

    bill = @order.bill_breakdown
    due_cents = (bill[:remaining] * 100).round
    pay_cents = (pay_amt * 100).round
    if pay_cents > [due_cents, 0].max
      @order.errors.add(:base, "Payment cannot exceed remaining amount (₹#{'%.2f' % ([due_cents, 0].max / 100.0)}).")
      return render :show
    end

    Payment.transaction do
      @order.save!
      @order.update_columns(cgst_cents: (bill[:cgst] * 100).round, igst_cents: (bill[:igst] * 100).round)
      p = Payment.create!(order_id: @order.id, customer_id: @order.customer_id, amount_cents: pay_cents, payment_method: pm)
      rn = "RCT-#{Time.zone.today.strftime('%Y%m%d')}-#{p.id.to_s.rjust(4, '0')}"
      p.update_columns(receipt_number: rn)
      paid = @order.payments.sum(:amount_cents).to_i
      total_cents = (bill[:total] * 100).round
      @order.update(status: (paid >= total_cents ? 'paid' : 'pending'))
      @order.customer.recompute_balance! if @order.customer.respond_to?(:recompute_balance!)
    end

    if @order.status == 'paid'
      redirect_to invoice_order_path(@order)
    else
      redirect_to @order, notice: 'Partial payment recorded. Receipt is in the payments list.'
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
