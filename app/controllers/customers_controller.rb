class CustomersController < ApplicationController
  before_action :set_customer, only: [:show, :edit, :update, :destroy]

  def index
    @q = params[:q].to_s.strip
    @status = %w[paid pending].include?(params[:status].to_s) ? params[:status].to_s : 'all'
    @sort = params[:sort].to_s == 'amount' ? 'amount' : 'name'
    @direction = params[:direction].to_s == 'asc' ? 'asc' : 'desc'
    @direction = 'asc' if @sort == 'name' && params[:direction].blank?
    @direction = 'desc' if @sort == 'amount' && params[:direction].blank?

    page = params[:page].to_i <= 0 ? 1 : params[:page].to_i
    per_page = 20

    customers = Customer.all
    if @q.present?
      token = @q.sub(/\A#+/, '').strip
      customers = customers.where(
        'first_name LIKE :q OR last_name LIKE :q OR email LIKE :q OR phone LIKE :q OR aadhaar_or_pan LIKE :q OR gst_number LIKE :q OR address LIKE :q OR COALESCE(client_code, \'\') LIKE :q OR COALESCE(client_code, \'\') LIKE :code OR CONCAT(\'#\', COALESCE(client_code, \'\')) LIKE :q',
        q: "%#{@q}%",
        code: "%#{token}%"
      )
    end

    pending_ids = Order.where(status: 'pending').select(:customer_id)
    paid_ids = Order.where(status: 'paid').select(:customer_id)
    @status_counts = {
      'all' => customers.count,
      'pending' => customers.where(id: pending_ids).count,
      'paid' => customers.where(id: paid_ids).where.not(id: pending_ids).count
    }

    case @status
    when 'pending'
      customers = customers.where(id: pending_ids)
    when 'paid'
      customers = customers.where(id: paid_ids).where.not(id: pending_ids)
    end

    customers = if @sort == 'amount'
                  customers.order(Arel.sql("COALESCE(balance_cents, 0) #{@direction == 'asc' ? 'ASC' : 'DESC'}"), :first_name, :last_name)
                else
                  customers.order(:first_name, :last_name)
                end

    @total_count = customers.count
    @page = page
    @per_page = per_page
    @customers = customers.includes(:orders).limit(per_page).offset((page - 1) * per_page)
  end

  def new
    @customer = Customer.new
  end

  def create
    @customer = Customer.new(customer_params)
    @customer.house_name_for_code = current_house_name
    if @customer.save
      redirect_to @customer, notice: 'Client saved to the book.'
    else
      render :new
    end
  end

  def show
    tab = params[:tab].to_s.downcase
    orders_scope = @customer.orders.order(created_at: :desc)
    @orders = case tab
              when 'paid' then orders_scope.where(status: 'paid')
              when 'pending' then orders_scope.where(status: 'pending')
              else orders_scope
              end
    @payments = @customer.payments.order(created_at: :desc).limit(20)
  end

  def edit
  end

  def update
    if @customer.update(customer_params)
      redirect_to @customer, notice: 'Client details saved.'
    else
      render :edit
    end
  end

  def destroy
    if @customer.orders.exists? || (Customer.reflect_on_association(:ledger_entries) && @customer.ledger_entries.exists?)
      redirect_to @customer, alert: 'This client has bills or a khata in the book and cannot be removed.'
    else
      @customer.destroy
      redirect_to customers_path, notice: 'Client removed from the book.'
    end
  end

  private

  def set_customer
    @customer = Customer.find(params[:id])
  end

  def customer_params
    params.require(:customer).permit(:first_name, :last_name, :email, :phone, :address, :aadhaar_or_pan, :gst_number)
  end

  def current_house_name
    current_user.try(:shop_profile).try(:shop_name).presence || current_user.try(:shop_name)
  end
end
