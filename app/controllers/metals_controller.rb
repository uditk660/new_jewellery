class MetalsController < ApplicationController
  before_action :refresh_master_columns
  before_action :set_metal, only: [:show, :update, :destroy]

  def index
    @metals = Metal.includes(:purities, :jewellery_categories).ordered
    @metals = @metals.where('name LIKE ?', "%#{params[:q].to_s.strip}%") if params[:q].present?
  end

  def new
    @metal = Metal.new(base_unit: 'gram', active: true)
    @metal.purities.build(active: true, hallmark_standard: 'BIS', position: 1)
    @metal.jewellery_categories.build(active: true, gender: 'Unisex', position: 1)
  end

  def show
    @metal.purities.build(active: true, hallmark_standard: 'BIS') if @metal.purities.empty?
    @metal.jewellery_categories.build(active: true, gender: 'Unisex') if @metal.jewellery_categories.empty?
  end

  def create
    @metal = Metal.new(metal_params)
    if @metal.save
      redirect_to metal_path(@metal), notice: 'Metal, hallmarks and categories saved.'
    else
      ensure_nested_rows
      render :new
    end
  end

  def update
    if @metal.update(metal_params)
      redirect_to metal_path(@metal), notice: 'Metal, hallmarks and categories updated.'
    else
      ensure_nested_rows
      render :show
    end
  end

  def destroy
    if @metal.jewelry_items.exists?
      redirect_to metal_path(@metal), alert: 'This metal is used on catalogue pieces and cannot be removed.'
    else
      @metal.destroy
      redirect_to metals_path, notice: 'Metal removed from the house masters.'
    end
  end

  private

  def refresh_master_columns
    Purity.reset_column_information unless Purity.column_names.include?('available_grams')
    JewelleryCategory.reset_column_information unless JewelleryCategory.column_names.include?('gender')
    Metal.reset_column_information unless Metal.column_names.include?('code')
  end

  def set_metal
    @metal = Metal.includes(:purities, :jewellery_categories).find(params[:id])
  end

  def ensure_nested_rows
    @metal.purities.build(active: true) if @metal.purities.reject(&:marked_for_destruction?).empty?
    @metal.jewellery_categories.build(active: true) if @metal.jewellery_categories.reject(&:marked_for_destruction?).empty?
  end

  def metal_params
    params.require(:metal).permit(
      :name, :code, :base_unit, :hsn_code, :colour, :notes, :display_order, :bis_mandatory, :active,
      purities_attributes: [
        :id, :name, :purity_percent, :fineness, :hallmark_standard, :updated_price,
        :available_grams, :wastage_percent, :making_charge_percent, :position, :remarks, :active, :_destroy
      ],
      jewellery_categories_attributes: [
        :id, :name, :description, :hsn_code, :gender, :default_making_charge_percent,
        :position, :active, :_destroy
      ]
    )
  end
end
