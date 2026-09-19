class JewelryItemsController < ApplicationController
  protect_from_forgery with: :exception

  CATALOGUE_STATUSES = %w[all available stock_out archived locked].freeze

  def index
    # simple search, sort and pagination
    per_page = (params[:per_page] || 25).to_i
    page = (params[:page].to_i <= 0) ? 1 : params[:page].to_i
    query = params[:q].to_s.strip
    @status = CATALOGUE_STATUSES.include?(params[:status].to_s) ? params[:status] : 'all'

  # eager load associations and metal -> metal_stocks -> store to avoid N+1 when rendering stock breakdown
  items = JewelryItem.includes(:purity, :jewellery_category, metal: { metal_stocks: :store })

    if query.present?
      items = items.joins("LEFT JOIN jewellery_categories ON jewellery_categories.id = jewelry_items.jewellery_category_id")
                   .joins("LEFT JOIN metals ON metals.id = jewelry_items.metal_id")
                   .joins("LEFT JOIN purities ON purities.id = jewelry_items.purity_id")
                   .where("jewelry_items.name LIKE :q OR jewelry_items.sku LIKE :q OR jewelry_items.description LIKE :q OR jewellery_categories.name LIKE :q OR metals.name LIKE :q OR purities.name LIKE :q", q: "%#{query}%")
    end

    items, @status_counts = apply_catalogue_status(items, @status)

    sort = params[:sort].to_s
    direction = params[:direction] == 'asc' ? 'ASC' : 'DESC'

    case sort
    when 'weight'
      items = items.order("weight_grams #{direction}")
    when 'price'
      items = items.order("price_cents #{direction}")
    when 'available'
      # available_sort_value: prefer `quantity` (pcs), else sum of metal stock available_grams
      items = items.select("jewelry_items.*, COALESCE(jewelry_items.quantity, (SELECT SUM(available_grams) FROM metal_stocks WHERE metal_stocks.metal_id = jewelry_items.metal_id), 0) AS available_sort_value")
                   .order("available_sort_value #{direction}")
    else
      items = items.order(created_at: :desc)
    end

    @total_count = items.except(:limit, :offset, :order).count
    @page = page
    @per_page = per_page
  @start_index = (@page - 1) * @per_page
    @items = items.limit(per_page).offset((page - 1) * per_page)

    render template: 'jewelry_items/index'
  end

  def show
    @item = JewelryItem.includes(:purity, :jewellery_category, metal: { metal_stocks: :store }).find(params[:id])
    render template: 'jewelry_items/show'
  end

  def new
    @item = JewelryItem.new(quantity: 1)
    load_catalogue_masters
    render template: 'jewelry_items/new'
  end

  def create
    @item = JewelryItem.new(jewelry_item_params)
    if @item.save
      redirect_to @item
    else
      load_catalogue_masters
      render template: 'jewelry_items/new'
    end
  end

  def edit
    Purity.reset_column_information unless Purity.column_names.include?('available_grams')
    @item = JewelryItem.includes(:purity, :jewellery_category, :metal).find(params[:id])
    return if redirect_if_not_amendable
    render template: 'jewelry_items/edit'
  end

  def update
    Purity.reset_column_information unless Purity.column_names.include?('available_grams')
    @item = JewelryItem.includes(:purity, :jewellery_category, :metal).find(params[:id])
    return if redirect_if_not_amendable
    if @item.update(jewelry_item_update_params)
      redirect_to @item
    else
      render template: 'jewelry_items/edit'
    end
  end

  def destroy
    @item = JewelryItem.find(params[:id])
    @item.destroy
    redirect_to jewelry_items_path
  end

  def archive
    @item = JewelryItem.find(params[:id])
    @item.update_columns(archived: true, updated_at: Time.current) if @item.has_attribute?(:archived)
    redirect_to jewelry_items_path(status: 'archived'), notice: "#{@item.name} is archived."
  end

  def unarchive
    @item = JewelryItem.find(params[:id])
    @item.update_columns(archived: false, updated_at: Time.current) if @item.has_attribute?(:archived)
    status = @item.quantity.to_i > 0 ? 'available' : 'stock_out'
    redirect_to jewelry_items_path(status: status), notice: "#{@item.name} is back in the catalogue."
  end

  private

  def redirect_if_not_amendable
    return false if @item.amendable?
    alert = if @item.archived?
              'This piece is archived. Restore it to the catalogue before amending.'
            else
              'This piece is locked. Activate its metal on Metals before amending it.'
            end
    redirect_to jewelry_item_path(@item), alert: alert
    true
  end

  def apply_catalogue_status(items, status)
    unless JewelryItem.column_names.include?('archived')
      return [items, { 'all' => 0, 'available' => 0, 'stock_out' => 0, 'archived' => 0, 'locked' => 0 }]
    end

    counted = items.except(:order)
    live = counted.where(archived: false)
    counts = {
      'available' => live.where('jewelry_items.quantity > 0').count,
      'stock_out' => live.where('jewelry_items.quantity <= 0').count,
      'archived' => counted.where(archived: true).count,
      'locked' => live.merge(JewelryItem.with_inactive_master).distinct.count
    }
    counts['all'] = counts['available'] + counts['stock_out']
    filtered = case status
               when 'available'
                 items.where(archived: false).where('jewelry_items.quantity > 0')
               when 'stock_out'
                 items.where(archived: false).where('jewelry_items.quantity <= 0')
               when 'archived'
                 items.where(archived: true)
               when 'locked'
                 items.where(archived: false).merge(JewelryItem.with_inactive_master)
               else
                 items.where(archived: false)
               end
    [filtered, counts]
  end

  def load_catalogue_masters
    Purity.reset_column_information unless Purity.column_names.include?('available_grams')
    @metals = Metal.active.ordered
    @purities = Purity.active.ordered.includes(:metal)
    @categories = JewelleryCategory.active.ordered
  end

  def jewelry_item_params
    params.require(:jewelry_item).permit(:name, :description, :sku, :quantity, :metal_id, :purity_id, :jewellery_category_id, :weight_grams)
  end

  def jewelry_item_update_params
    params.require(:jewelry_item).permit(:name, :description, :quantity, :weight_grams)
  end
end
