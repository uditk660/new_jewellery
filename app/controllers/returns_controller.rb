require 'ostruct'

class ReturnsController < ApplicationController

  def index
    @q = params[:q].to_s.strip
    raw = Array(session[:return_records]).map { |r| stringify_record(r) }
    records = raw.each_with_index.map { |r, i| r.merge('id' => r['id'].presence || i.to_s) }

    customers = Customer.where(id: records.map { |r| r['customer_id'] }.reject(&:blank?))
                        .index_by { |c| c.id.to_s }
    items = JewelryItem.where(id: records.map { |r| r['jewelry_item_id'] }.reject(&:blank?))
                       .index_by { |it| it.id.to_s }
    orders = Order.where(id: records.map { |r| r['order_id'] }.reject(&:blank?))
                  .index_by { |o| o.id.to_s }

    decorated = records.reverse.map do |r|
      r.merge(
        '_customer' => customers[r['customer_id'].to_s],
        '_item' => items[r['jewelry_item_id'].to_s],
        '_order' => orders[r['order_id'].to_s]
      )
    end

    if @q.present?
      q = @q.downcase
      decorated = decorated.select { |r| searchable_return(r).include?(q) }
    end

    @records = decorated
    @cash_count = decorated.count { |r| r['action'].to_s == 'cash' }
    @exchange_count = decorated.count { |r| r['action'].to_s == 'exchange' }
  end

  def new
    @return_form = OpenStruct.new(
      customer_id: params[:customer_id],
      walk_in_name: nil,
      walk_in_phone: nil,
      order_id: params[:order_id],
      jewelry_item_id: params[:jewelry_item_id],
      quantity: 1,
      reason: nil,
      action: 'cash',
      amount: nil,
      notes: nil
    )
    load_form_collections
  end

  def create
    payload = params.require(:return).permit(
      :customer_id, :walk_in_name, :walk_in_phone,
      :order_id, :reason, :action, :amount, :notes, :jewelry_item_id, :quantity
    )
    record = stringify_record(payload.to_h).merge(
      'id' => SecureRandom.hex(8),
      'created_at' => Time.zone.now.iso8601
    )
    record['customer_id'] = record['customer_id'].presence
    if record['customer_id'].present?
      record['walk_in_name'] = nil
      record['walk_in_phone'] = nil
    else
      record['walk_in_name'] = record['walk_in_name'].to_s.strip.presence
      record['walk_in_phone'] = record['walk_in_phone'].to_s.gsub(/\s+/, '').presence
    end

    if payload[:jewelry_item_id].present? && payload[:quantity].present?
      ji = JewelryItem.find_by(id: payload[:jewelry_item_id])
      qty = payload[:quantity].to_i
      if ji && qty > 0
        JewelryItem.transaction do
          ji.lock!
          ji.restore_to_tray!(qty)

          inv = InventoryItem.find_by(jewelry_item_id: ji.id)
          if inv && ji.weight_grams.present?
            grams_to_add = (ji.weight_grams.to_f * qty).round
            inv.adjust!(grams_to_add, movement_type: 'return', note: "Return for bill #{payload[:order_id]}")
          end
        end

        record['stock_updated'] = true
      end
    end

    session[:return_records] ||= []
    session[:return_records] << record
    kind = record['action'].to_s == 'exchange' ? 'Exchange' : 'Cash refund'
    flash[:notice] = "#{kind} recorded for the house book."
    redirect_to returns_path
  end

  def show
    raw = Array(session[:return_records]).map { |r| stringify_record(r) }
    indexed = raw.each_with_index.map { |r, i| r.merge('id' => r['id'].presence || i.to_s) }
    @record = indexed.find { |r| r['id'].to_s == params[:id].to_s }
    unless @record
      redirect_to returns_path, alert: 'That return is no longer on the book.'
      return
    end

    @customer = Customer.find_by(id: @record['customer_id']) if @record['customer_id'].present?
    @item = JewelryItem.includes(:metal, :purity).find_by(id: @record['jewelry_item_id']) if @record['jewelry_item_id'].present?
    @order = Order.find_by(id: @record['order_id']) if @record['order_id'].present?
    @shop = current_user.try(:shop_profile) if defined?(current_user)
    @shop ||= ShopProfile.first if defined?(ShopProfile)
  end

  private

  def load_form_collections
    @customers = Customer.order(:first_name, :last_name)
    @items = JewelryItem.includes(:metal, :purity).order(:name)
    @orders = Order.includes(:customer).order(created_at: :desc).limit(80)
    @items_payload = @items.map do |it|
      {
        id: it.id,
        name: it.name,
        sku: it.sku,
        weight: it.weight_grams.to_f,
        stock: it.quantity.to_i,
        metal: it.metal&.name,
        purity: it.purity&.name,
        price: it.computed_price.to_f
      }
    end
  end

  def stringify_record(record)
    record.to_h.stringify_keys
  end

  def searchable_return(r)
    client = r['_customer']
    item = r['_item']
    order = r['_order']
    bill = order&.invoice_number.presence || r['order_id'].to_s
    [
      client&.full_name, client&.phone,
      r['walk_in_name'], r['walk_in_phone'],
      item&.name, item&.sku,
      bill, r['action'], r['reason'], r['id']
    ].compact.join(' ').downcase
  end
end
