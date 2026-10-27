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

    saved = raise_bill_safely

    if saved
      redirect_to saved, notice: 'Ticket raised from the counter. Record payment when the client settles.'
    else
      render :index, status: :unprocessable_entity
    end
  end

  # No card gateway is connected. A bill is settled only through a recorded
  # payment on the bill, so the ledger, receipts and stock stay in step.
  def charge
    order = Order.find_by(id: params[:order_id])
    target = order ? order_path(order) : orders_path
    redirect_to target, alert: 'Card charging is not connected. Record the payment on the bill instead.'
  end

  private

  def setup_counter
    @order ||= Order.new(
      status: 'pending',
      cgst_rate: Order::DEFAULT_CGST_RATE,
      sgst_rate: Order::DEFAULT_SGST_RATE,
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
