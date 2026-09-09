class PaymentsController < ApplicationController
  def show
    @payment = Payment.find(params[:id])
    render template: 'payments/show'
  end

  def invoice
    load_payment
    prepare_receipt(public_view: false)
    render template: 'payments/invoice', layout: false
  end

  def shared_invoice
    token = params[:token].to_s
    raise ActiveRecord::RecordNotFound if token.blank?

    @payment = payment_scope.find_by!(share_token: token)
    prepare_receipt(public_view: true)
    render template: 'payments/invoice', layout: false
  end

  private

  def load_payment
    @payment = payment_scope.find(params[:id])
  end

  def payment_scope
    Payment.includes(:customer, order: [:customer, :payments, { line_items: { jewelry_item: [:metal, :purity, :jewellery_category] } }])
  end

  def prepare_receipt(public_view:)
    @public_invoice = public_view
    @order = @payment.order
    @shop = current_user.try(:shop_profile) unless public_view
    @shop ||= ShopProfile.first if defined?(ShopProfile)
    token = @payment.ensure_share_token!
    @qr_payload = shared_receipt_url(token)
    @tax_invoice_url = if @order
                         public_view ? shared_invoice_url(@order.ensure_share_token!) : invoice_order_path(@order)
                       end
  end
end
