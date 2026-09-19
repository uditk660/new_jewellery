class MetalStocksController < ApplicationController
  def index
    @q = params[:q].to_s.strip
    @status = %w[all light empty].include?(params[:status].to_s) ? params[:status].to_s : 'all'
    @metal_id = params[:metal_id].presence
    @store_id = params[:store_id].presence

    scope = MetalStock.includes(:metal, :store, :metal_stock_movements)
                      .joins(:metal, :store)
                      .order('stores.name, metals.name')

    if @q.present?
      like = "%#{@q.downcase}%"
      scope = scope.where("LOWER(metals.name) LIKE :q OR LOWER(stores.name) LIKE :q OR LOWER(COALESCE(stores.location, '')) LIKE :q", q: like)
    end
    scope = scope.where(metal_id: @metal_id) if @metal_id
    scope = scope.where(store_id: @store_id) if @store_id

    rows = scope.to_a
    @status_counts = {
      'all' => rows.size,
      'light' => rows.count(&:light?),
      'empty' => rows.count(&:empty?)
    }
    @metal_stocks = case @status
                    when 'light' then rows.select(&:light?)
                    when 'empty' then rows.select(&:empty?)
                    else rows
                    end

    @total_grams = rows.sum { |ms| ms.available_grams.to_i }
    @total_value = rows.sum(&:stock_value)
    @store_count = rows.map(&:store_id).uniq.size
    @metals = Metal.ordered
    @stores = Store.order(:name)
    @unopened = unopened_pairs
  end

  def new
    existing = MetalStock.find_by(metal_id: params[:metal_id], store_id: params[:store_id]) if params[:metal_id].present? && params[:store_id].present?
    if existing
      redirect_to existing, notice: 'That metal already has a card at this store.'
      return
    end

    @metal_stock = MetalStock.new(
      available_grams: 0,
      price_cents_per_gram: 0,
      metal_id: params[:metal_id],
      store_id: params[:store_id]
    )
    load_masters
  end

  def create
    @metal_stock = MetalStock.new(metal_stock_params)
    existing = MetalStock.find_by(metal_id: @metal_stock.metal_id, store_id: @metal_stock.store_id)
    if existing
      redirect_to existing, alert: 'That metal already has a card at this store.'
      return
    end

    saved = false
    MetalStock.transaction do
      saved = @metal_stock.save
      if saved && @metal_stock.available_grams.to_i.positive?
        @metal_stock.metal_stock_movements.create!(
          change_grams: @metal_stock.available_grams.to_i,
          movement_type: 'in',
          note: 'Opening weight in the vault'
        )
      end
    end

    if saved
      redirect_to @metal_stock, notice: "#{@metal_stock.metal&.name} at #{@metal_stock.store&.name} is on the vault at #{@metal_stock.available_grams.to_i} g."
    else
      load_masters
      render :new
    end
  rescue ActiveRecord::RecordNotUnique
    existing = MetalStock.find_by(metal_id: @metal_stock.metal_id, store_id: @metal_stock.store_id)
    redirect_to existing || metal_stocks_path, alert: 'That metal already has a card at this store.'
  end

  def show
    load_card
  end

  def update
    load_card
    if @metal_stock.update(params.require(:metal_stock).permit(:price_per_gram, :price_cents_per_gram))
      redirect_to @metal_stock, notice: 'Vault rate updated. Catalogue and the board fall back to this ₹/g when hallmark has no rate.'
    else
      flash.now[:alert] = @metal_stock.errors.full_messages.to_sentence.presence || 'Could not update the vault rate.'
      render :show
    end
  end

  def adjust
    load_card
    render :show
  end

  def do_adjust
    load_card
    change = params[:metal_stock].present? ? params[:metal_stock][:change_grams] : params[:change_grams]
    type = params[:metal_stock].present? ? params[:metal_stock][:movement_type] : params[:movement_type]
    note = params[:metal_stock].present? ? params[:metal_stock][:note] : params[:note]
    type = type.presence || 'adjustment'

    if change.to_i.zero?
      flash.now[:alert] = 'Enter a weight change in grams.'
      return render :show
    end

    @metal_stock.adjust!(change, movement_type: type, note: note)
    redirect_to @metal_stock, notice: 'Vault updated.'
  rescue ActiveRecord::RecordInvalid
    @metal_stock.reload if @metal_stock&.persisted?
    @movements = @metal_stock.metal_stock_movements.order(created_at: :desc)
    flash.now[:alert] = @metal_stock.errors.full_messages.to_sentence.presence || 'Could not apply this movement.'
    render :show
  end

  private

  def metal_stock_params
    params.require(:metal_stock).permit(:metal_id, :store_id, :available_grams, :price_per_gram, :price_cents_per_gram)
  end

  def load_card
    @metal_stock = MetalStock.includes(:metal, :store, :metal_stock_movements).find(params[:id])
    @movements = @metal_stock.metal_stock_movements.order(created_at: :desc)
  end

  def load_masters
    @metals = Metal.ordered
    @stores = Store.order(:name)
    tracked = MetalStock.pluck(:metal_id, :store_id)
    latest_by_metal = MetalStock.order(created_at: :desc).to_a.uniq(&:metal_id).index_by(&:metal_id)
    @openable = []
    @metals.each do |metal|
      @stores.each do |store|
        next if tracked.include?([metal.id, store.id])
        hint = latest_by_metal[metal.id]
        @openable << {
          metal_id: metal.id,
          store_id: store.id,
          metal: metal.name,
          store: store.name,
          colour: metal.chip_colour,
          rate: hint && hint.price_cents_per_gram.to_i.positive? ? hint.price_per_gram : 0
        }
      end
    end
  end

  def unopened_pairs
    metals = Metal.ordered.to_a
    stores = Store.order(:name).to_a
    tracked = MetalStock.pluck(:metal_id, :store_id)
    pairs = []
    metals.each do |metal|
      stores.each do |store|
        next if tracked.include?([metal.id, store.id])
        pairs << { metal: metal, store: store }
      end
    end
    pairs.select! { |pair| pair[:metal].id.to_s == @metal_id.to_s } if @metal_id
    pairs.select! { |pair| pair[:store].id.to_s == @store_id.to_s } if @store_id
    pairs.first(12)
  end
end
