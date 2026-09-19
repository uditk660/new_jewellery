class StoresController < ApplicationController
  def index
    @q = params[:q].to_s.strip
    @status = %w[all bare light empty].include?(params[:status].to_s) ? params[:status].to_s : 'all'

    scope = Store.includes(metal_stocks: :metal).ordered
    if @q.present?
      like = "%#{@q.downcase}%"
      scope = scope.where("LOWER(stores.name) LIKE :q OR LOWER(COALESCE(stores.location, '')) LIKE :q", q: like)
    end

    rows = scope.to_a
    @status_counts = {
      'all' => rows.size,
      'bare' => rows.count(&:bare?),
      'light' => rows.count(&:light_vault?),
      'empty' => rows.count(&:empty_vault?)
    }
    @stores = case @status
              when 'bare' then rows.select(&:bare?)
              when 'light' then rows.select(&:light_vault?)
              when 'empty' then rows.select(&:empty_vault?)
              else rows
              end

    @house_count = rows.size
    @total_grams = rows.sum(&:vault_grams)
    @total_value = rows.sum(&:vault_value)
    @metals = Metal.ordered
  end

  def new
    @store = Store.new
    load_form
  end

  def create
    @store = Store.new(store_params)
    if @store.save
      redirect_to @store, notice: "#{@store.name} is on the house book. Open vault cards for the metals it holds."
    else
      load_form
      render :new
    end
  rescue ActiveRecord::RecordNotUnique
    @store.errors.add(:name, 'is already on the house book')
    load_form
    render :new
  end

  def show
    load_store
  end

  def edit
    load_store
    load_form
  end

  def update
    load_store
    if @store.update(store_params)
      redirect_to @store, notice: "#{@store.name} has been amended."
    else
      load_form
      render :edit
    end
  rescue ActiveRecord::RecordNotUnique
    @store.errors.add(:name, 'is already on the house book')
    load_form
    render :edit
  end

  private

  def store_params
    params.require(:store).permit(:name, :location)
  end

  def load_store
    @store = Store.includes(metal_stocks: :metal).find(params[:id])
    @vaults = @store.metal_stocks.sort_by { |ms| ms.metal&.name.to_s }
    @missing = @store.missing_metals.to_a
  end

  def load_form
    @metals = Metal.ordered
    @existing_names = Store.ordered.pluck(:name)
  end
end
