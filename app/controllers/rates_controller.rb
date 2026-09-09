class RatesController < ApplicationController
  before_action :refresh_purity_columns

  def index
    @metals = Metal.includes(:purities).ordered
    @today = Time.zone.today
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

  def load_rate_masters
    @metals = Metal.active.ordered.includes(:purities)
  end

  def apply_rate_selection
    @selected_metal_id = params[:metal_id].presence&.to_i || @metals.first&.id
    @selected_purity_id = params[:purity_id].presence&.to_i
    metal = @metals.find { |m| m.id == @selected_metal_id }
    @purities_for_metal = metal ? metal.purities.ordered : Purity.none
    purity = @purities_for_metal.find { |p| p.id == @selected_purity_id } if @selected_purity_id
    @prefill_price = purity&.updated_price
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
