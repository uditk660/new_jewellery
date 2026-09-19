class PosController < OrdersController
  def index
    load_bill_form
    setup_counter
  end

  def create_order
    load_bill_form
    setup_counter
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
      redirect_to saved, notice: 'Ticket raised from the counter. Record payment when the client settles.'
    else
      render :index, status: :unprocessable_entity
    end
  end

  def charge
    @order = Order.find(params[:order_id])
    payment_info = params[:payment] || {}

    result = BillingService.new(@order, payment_info).charge!
    if result[:success]
      @order.update(status: 'paid')
      redirect_to @order, notice: 'Payment processed successfully.'
    else
      @order.update(status: 'failed')
      redirect_to @order, alert: "Payment failed: #{result[:error]}"
    end
  rescue ActiveRecord::RecordNotFound
    redirect_to orders_path, alert: 'Order not found'
  end

  private

  def setup_counter
    @order ||= Order.new(
      status: 'pending',
      cgst_rate: Order::DEFAULT_CGST_RATE,
      igst_rate: Order::DEFAULT_IGST_RATE,
      discount: 0,
      charges: 0
    )
    @customer_mode ||= 'existing'
    @selected_customer_id ||= params[:customer_id].presence
    @draft_customer ||= Customer.new
    @draft_lines ||= []
    @metals = Metal.active.ordered.includes(:purities)
    @board_date = Time.zone.today
    @board_rows = @metals.flat_map do |metal|
      metal.purities.active.ordered.map do |purity|
        {
          metal: metal.name,
          colour: metal.chip_colour,
          hallmark: purity.name,
          rate: purity.updated_price.to_f
        }
      end
    end.select { |row| row[:rate].positive? }
  end
end
