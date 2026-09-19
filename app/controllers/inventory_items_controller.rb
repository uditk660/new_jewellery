class InventoryItemsController < ApplicationController
  def index
    @q = params[:q].to_s.strip
    @status = %w[all light empty].include?(params[:status].to_s) ? params[:status].to_s : 'all'

    scope = InventoryItem.left_joins(jewelry_item: [:metal, :purity, :jewellery_category])
                         .includes(jewelry_item: [:metal, :purity, :jewellery_category])
                         .order(Arel.sql("COALESCE(jewelry_items.name, '') ASC"))

    if @q.present?
      like = "%#{@q.downcase}%"
      scope = scope.where(
        'LOWER(jewelry_items.name) LIKE :q OR LOWER(jewelry_items.sku) LIKE :q OR LOWER(COALESCE(inventory_items.location, "")) LIKE :q OR LOWER(COALESCE(metals.name, "")) LIKE :q OR LOWER(COALESCE(purities.name, "")) LIKE :q',
        q: like
      )
    end

    rows = scope.to_a
    @status_counts = {
      'all' => rows.size,
      'light' => rows.count(&:light?),
      'empty' => rows.count(&:empty?)
    }
    @inventory_items = case @status
                       when 'light' then rows.select(&:light?)
                       when 'empty' then rows.select(&:empty?)
                       else rows
                       end

    @total_grams = rows.sum { |it| it.available_grams.to_i }
    @tray_pcs = rows.sum { |it| it.jewelry_item&.quantity.to_i }
    @tray_value = rows.sum { |it| it.jewelry_item&.stock_amount.to_f || 0 }

    tracked_ids = InventoryItem.distinct.pluck(:jewelry_item_id)
    untracked = JewelryItem.kept.includes(:metal, :purity)
    untracked = untracked.where.not(id: tracked_ids) if tracked_ids.any?
    @untracked = untracked.order(:name).limit(24)
  end

  def new
    @inventory_item = InventoryItem.new(location: 'Main tray')
    if params[:jewelry_item_id].present?
      @inventory_item.jewelry_item_id = params[:jewelry_item_id]
      piece = JewelryItem.find_by(id: params[:jewelry_item_id])
      @inventory_item.available_grams = opening_grams_for(piece) if piece
    end
    load_openable_pieces
  end

  def create
    @inventory_item = InventoryItem.new(inventory_item_params)
    existing = InventoryItem.find_by(jewelry_item_id: @inventory_item.jewelry_item_id)
    if existing
      redirect_to existing, alert: 'That catalogue piece is already on the stock book.'
      return
    end

    if @inventory_item.available_grams.blank?
      @inventory_item.available_grams = opening_grams_for(@inventory_item.jewelry_item)
    end

    saved = false
    InventoryItem.transaction do
      saved = @inventory_item.save
      if saved && @inventory_item.available_grams.to_i.positive?
        @inventory_item.stock_movements.create!(
          change_grams: @inventory_item.available_grams.to_i,
          movement_type: 'in',
          note: 'Opening weight on the stock book'
        )
      end
    end

    if saved
      grams = @inventory_item.available_grams.to_i
      redirect_to @inventory_item, notice: "#{@inventory_item.jewelry_item&.name || 'Piece'} is on the stock book at #{grams} g."
    else
      load_openable_pieces
      render :new
    end
  end

  def show
    @inventory_item = InventoryItem.includes(:stock_movements, jewelry_item: [:metal, :purity, :jewellery_category]).find(params[:id])
    @movements = @inventory_item.stock_movements.order(created_at: :desc)
    @piece = @inventory_item.jewelry_item
  end

  private

  def inventory_item_params
    params.require(:inventory_item).permit(:jewelry_item_id, :available_grams, :location)
  end

  def opening_grams_for(piece)
    return 0 unless piece
    (piece.weight_grams.to_f * [piece.quantity.to_i, 0].max).round
  end

  def load_openable_pieces
    tracked_ids = InventoryItem.distinct.pluck(:jewelry_item_id)
    scope = JewelryItem.kept.includes(:metal, :purity).order(:name)
    scope = scope.where.not(id: tracked_ids) if tracked_ids.any?
    @items = scope.to_a
    current_id = @inventory_item&.jewelry_item_id
    if current_id.present? && @items.none? { |it| it.id == current_id.to_i }
      piece = JewelryItem.includes(:metal, :purity).find_by(id: current_id)
      @items.unshift(piece) if piece
    end
    @items_payload = @items.map { |it| piece_payload(it) }
  end

  def piece_payload(it)
    {
      id: it.id,
      name: it.name,
      sku: it.sku.to_s,
      metal: it.metal&.name.to_s,
      purity: it.purity&.try(:hallmark_label).to_s,
      weight: it.weight_grams.to_f,
      quantity: it.quantity.to_i,
      opening: opening_grams_for(it)
    }
  end
end
