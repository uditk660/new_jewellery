class CustomersController < ApplicationController
  before_action :set_customer, only: [:show, :edit, :update, :destroy]

  def index
    @q = params[:q].to_s.strip
    customers = Customer.order(:first_name, :last_name)
    if @q.present?
      like = "%#{@q}%"
      customers = customers.where(
        'first_name LIKE :q OR last_name LIKE :q OR email LIKE :q OR phone LIKE :q OR aadhaar_or_pan LIKE :q OR gst_number LIKE :q OR address LIKE :q',
        q: like
      )
    end
    @customers = customers.limit(200)
  end

  def new
    @customer = Customer.new
  end

  def create
    @customer = Customer.new(customer_params)
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
    if @customer.orders.exists?
      redirect_to @customer, alert: 'This client has bills in the book and cannot be removed.'
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
end
