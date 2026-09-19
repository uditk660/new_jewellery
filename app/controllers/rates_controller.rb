class RatesController < ApplicationController
  before_action :refresh_purity_columns
  helper_method :rate_rupees_for

  def index
    @metals = Metal.includes(:purities).ordered
    @today = Time.zone.today
    load_stock_board
  end

  def new
    @rate = Rate.new(date: Time.zone.today)
    load_rate_masters
    apply_rate_selection
    render template: 'rates/new'
  end

  def create
    metal, purity, rupees, date = parsed_rate_input
    unless metal && purity && rupees && rupees.positive?
      redirect_to rates_path, alert: 'Choose a hallmark and enter today’s rate in rupees per gram.'
      return
    end
    if metal.rate_board_locked? || purity.rate_board_locked?
      redirect_to rates_path, alert: "#{metal.name} is inactive. Activate it under Metals before setting a rate."
      return
    end

    label = "#{metal.name} - #{purity.name}"
    @rate = Rate.find_or_initialize_by(date: date, metal_type: label)
    @rate.price_cents_per_gram = (rupees * 100).round

    saved = false
    Rate.transaction do
      saved = @rate.save && purity.update(updated_price: rupees)
      raise ActiveRecord::Rollback unless saved
    end

    if saved
      redirect_to rates_path, notice: "#{purity.hallmark_label} is now ₹#{'%.2f' % rupees}/g."
    else
      load_rate_masters
      @selected_metal_id = metal.id
      @selected_purity_id = purity.id
      @prefill_price = rupees
      @purities_for_metal = metal.purities.ordered
      flash.now[:alert] = [@rate.errors.full_messages, purity.errors.full_messages].flatten.compact.to_sentence.presence || 'Could not save this rate.'
      render template: 'rates/new'
    end
  end

  def edit
    redirect_to rates_path
  end

  def update
    create
  end

  private

  def refresh_purity_columns
    Purity.reset_column_information unless Purity.column_names.include?('available_grams')
  end

  def load_stock_board
    stock_scope = JewelryItem.includes(:purity, :jewellery_category, metal: :metal_stocks)
    stock_scope = stock_scope.kept if JewelryItem.column_names.include?('archived')
    @stock_items = stock_scope.order(:name).to_a
    @stock_items.sort_by! { |item| [item.quantity.to_i > 0 ? 0 : 1, item.name.to_s.downcase] }
    @stock_piece_count = @stock_items.sum { |item| item.quantity.to_i }
    @stock_weight_grams = @stock_items.sum { |item| item.weight_grams.to_f * item.quantity.to_i }
    @total_stock_value = @stock_items.sum(&:stock_amount)
  end

  def load_rate_masters
    @metals = Metal.active.ordered.includes(:purities, :metal_stocks)
    @today_rates_by_label = Rate.where(date: Time.zone.today).order(:id).index_by(&:metal_type)
  end

  def apply_rate_selection
    @selected_metal_id = params[:metal_id].presence&.to_i
    @selected_purity_id = params[:purity_id].presence&.to_i
    metal = @metals.find { |m| m.id == @selected_metal_id }
    @purities_for_metal = metal ? metal.purities.active.ordered : Purity.none
    purity = @purities_for_metal.find { |p| p.id == @selected_purity_id } if @selected_purity_id
    @prefill_price = rate_rupees_for(metal, purity)
  end

  def rate_rupees_for(metal, purity)
    return nil unless metal && purity
    price = purity.updated_price.to_f
    return price if price.positive?

    label = "#{metal.name} - #{purity.name}"
    board = (@today_rates_by_label || {})[label]
    return board.price_per_gram if board && board.price_cents_per_gram.to_i.positive?

    stock = metal.metal_stocks.to_a.max_by(&:created_at)
    return stock.price_per_gram if stock && stock.price_cents_per_gram.to_i.positive?

    nil
  end

  def parsed_rate_input
    metal = Metal.find_by(id: params[:metal_id])
    purity = Purity.find_by(id: params[:purity_id])
    purity = nil if metal && purity && purity.metal_id != metal.id
    rupees = params[:price_per_gram].to_s.gsub(',', '').to_f
    date = begin
      Date.parse(params.dig(:rate, :date).to_s)
    rescue ArgumentError, TypeError
      Time.zone.today
    end
    [metal, purity, rupees, date]
  end
end
